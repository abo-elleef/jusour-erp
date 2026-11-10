# frozen_string_literal: true

module Accounting
  # Who sold what, where, and what went wrong — the three questions a restaurant
  # owner asks once the till is live:
  #
  # - by_branch:  net sales per branch, split by order type (table / pickup / delivery)
  # - by_cashier: orders, net sales, average ticket and discount rate per cashier,
  #               next to the voids and refunds each person performed
  # - exceptions: every void and refund in the range, with who did it and why
  #
  # Sales use the same definition as Accounting::SalesReportService (completed
  # orders in the business-day range, net = subtotal − discounts), so the totals
  # here always agree with the Sales report. Voids and refunds are read from the
  # order_events trail written by Admin::OrdersController#void and
  # Payments::RefundService — the only two places they happen.
  class SalesPerformanceService
    ORDER_TYPES = Order::ORDER_TYPES
    EXCEPTION_KINDS = %w[void refund].freeze

    BRANCH_SORTS = %w[name orders net_sales avg_ticket].freeze
    CASHIER_SORTS = %w[name orders net_sales avg_ticket discount_rate voids refunds].freeze
    EXCEPTION_SORTS = {
      "created_at" => "order_events.created_at",
      "kind"       => "order_events.event_type",
      "amount"     => "amount_cents"
    }.freeze

    # A refund event's description is "Refunded <cents> cents: <reason>"; a void's
    # is the reason itself. Pulling the amount out in SQL keeps the totals in the
    # database instead of loading every event.
    REFUND_AMOUNT_SQL = "COALESCE(substring(order_events.description from '^Refunded ([0-9]+) cents')::integer, 0)"
    EVENT_AMOUNT_SQL = <<~SQL.squish.freeze
      (CASE WHEN order_events.event_type = 'void'
            THEN COALESCE(orders.total_cents, 0)
            ELSE #{REFUND_AMOUNT_SQL} END)
    SQL

    BranchRow = Struct.new(:location_id, :name, :orders, :net_cents, :discount_cents, :by_type, keyword_init: true) do
      def avg_ticket_cents = orders.positive? ? net_cents / orders : 0
    end

    CashierRow = Struct.new(:user_id, :name, :orders, :gross_cents, :net_cents, :discount_cents, :voids, :refunds,
                            keyword_init: true) do
      def avg_ticket_cents = orders.positive? ? net_cents / orders : 0
      def discount_rate = gross_cents.positive? ? discount_cents * 100.0 / gross_cents : 0.0
    end

    def initialize(start_date, end_date, location_id: nil)
      @range = BusinessDay.range_between(start_date, end_date)
      @location_id = location_id.presence
    end

    # [rows, totals]. Rows are sorted by the caller's whitelisted key.
    def by_branch(sort: "net_sales", direction: "desc")
      grouped = completed_orders.group(:location_id, :order_type)
        .pluck(:location_id, :order_type, Arel.sql("COUNT(*)"),
               Arel.sql("SUM(#{RevenueCalculator::ORDER_NET_SALES})"), Arel.sql("SUM(orders.discount_cents)"))

      names = Location.where(id: grouped.map(&:first).compact).pluck(:id, :name).to_h
      rows = grouped.group_by(&:first).map do |location_id, parts|
        by_type = ORDER_TYPES.index_with { { orders: 0, net_cents: 0 } }
        parts.each do |_, type, count, net, _|
          by_type[type] = { orders: count.to_i, net_cents: net.to_i } if by_type.key?(type)
        end
        BranchRow.new(
          location_id: location_id, name: names[location_id],
          orders: parts.sum { |p| p[2].to_i }, net_cents: parts.sum { |p| p[3].to_i },
          discount_cents: parts.sum { |p| p[4].to_i }, by_type: by_type
        )
      end

      [sort_rows(rows, sort, direction, BRANCH_SORTS, branch_sort_value), branch_totals(rows)]
    end

    def by_cashier(sort: "net_sales", direction: "desc")
      sales = completed_orders.group(:user_id)
        .pluck(:user_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(orders.subtotal_cents)"),
               Arel.sql("SUM(#{RevenueCalculator::ORDER_NET_SALES})"), Arel.sql("SUM(orders.discount_cents)"))
        .index_by(&:first)
      counts = exception_events.group("order_events.user_id", "order_events.event_type").count

      user_ids = (sales.keys + counts.keys.map(&:first)).compact.uniq
      names = User.where(id: user_ids).pluck(:id, :name).to_h

      rows = user_ids.map do |user_id|
        _, orders, gross, net, discount = sales[user_id]
        CashierRow.new(
          user_id: user_id, name: names[user_id],
          orders: orders.to_i, gross_cents: gross.to_i, net_cents: net.to_i, discount_cents: discount.to_i,
          voids: counts[[user_id, "void"]].to_i, refunds: counts[[user_id, "refund"]].to_i
        )
      end

      sort_rows(rows, sort, direction, CASHIER_SORTS, cashier_sort_value)
    end

    # Totals for the exceptions tab header: counts and value of voids and
    # refunds, and what share of the period's gross sales they represent.
    def exceptions_summary
      @exceptions_summary ||= begin
        by_kind = exception_events.group("order_events.event_type")
          .pluck("order_events.event_type", Arel.sql("COUNT(*)"), Arel.sql("SUM(#{EVENT_AMOUNT_SQL})"))
          .to_h { |kind, count, cents| [kind, { count: count.to_i, cents: cents.to_i }] }
        gross = completed_orders.sum(:subtotal_cents).to_i
        lost = by_kind.values.sum { |v| v[:cents] }
        {
          void: by_kind.fetch("void", { count: 0, cents: 0 }),
          refund: by_kind.fetch("refund", { count: 0, cents: 0 }),
          gross_cents: gross,
          lost_pct: gross.positive? ? lost * 100.0 / gross : nil
        }
      end
    end

    # Relation for the paginated list. Each row carries `amount_cents`.
    def exceptions(kind: nil, sort: "created_at", direction: "desc")
      scope = exception_events
      scope = scope.where(order_events: { event_type: kind }) if EXCEPTION_KINDS.include?(kind)
      order_sql = EXCEPTION_SORTS.fetch(sort, EXCEPTION_SORTS["created_at"])
      dir = direction == "asc" ? "ASC" : "DESC"

      scope.select("order_events.*", "#{EVENT_AMOUNT_SQL} AS amount_cents")
        .preload(:user, order: %i[user location])
        .reorder(Arel.sql("#{order_sql} #{dir}"), Arel.sql("order_events.id DESC"))
    end

    private

    # Same population as Accounting::SalesReportService#completed_orders.
    def completed_orders
      @completed_orders ||= scope_to_location(Order.completed.where(created_at: @range))
    end

    # Void and refund events inside the range, for orders in the company
    # (Order's tenant default scope applies through the join).
    def exception_events
      scope = OrderEvent.joins(:order)
        .where(event_type: EXCEPTION_KINDS, created_at: @range)
      scope = scope.where(orders: { location_id: @location_id }) if @location_id
      scope
    end

    def scope_to_location(scope)
      @location_id ? scope.where(location_id: @location_id) : scope
    end

    def branch_totals(rows)
      {
        orders: rows.sum(&:orders),
        net_cents: rows.sum(&:net_cents),
        discount_cents: rows.sum(&:discount_cents),
        by_type: ORDER_TYPES.index_with do |type|
          { orders: rows.sum { |r| r.by_type[type][:orders] }, net_cents: rows.sum { |r| r.by_type[type][:net_cents] } }
        end
      }
    end

    def branch_sort_value
      { "name" => :name.to_proc >> ->(v) { v.to_s.downcase }, "orders" => :orders.to_proc,
        "net_sales" => :net_cents.to_proc, "avg_ticket" => :avg_ticket_cents.to_proc }
    end

    def cashier_sort_value
      { "name" => :name.to_proc >> ->(v) { v.to_s.downcase }, "orders" => :orders.to_proc,
        "net_sales" => :net_cents.to_proc, "avg_ticket" => :avg_ticket_cents.to_proc,
        "discount_rate" => :discount_rate.to_proc, "voids" => :voids.to_proc, "refunds" => :refunds.to_proc }
    end

    def sort_rows(rows, sort, direction, allowed, extractors)
      key = allowed.include?(sort) ? sort : allowed.fetch(allowed.index("net_sales"))
      sorted = rows.sort_by { |row| [extractors.fetch(key).call(row), row.name.to_s.downcase] }
      direction == "asc" ? sorted : sorted.reverse
    end
  end
end
