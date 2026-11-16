# frozen_string_literal: true

module Dashboard
  # Today's sales so far, while the day is still going.
  #
  # The sales report counts completed orders, and most orders get completed in
  # bulk when the drawer closes, so during the day it shows almost nothing. This
  # counts every *placed* order instead (submitted, in prep, ready or completed;
  # never a draft or a cancelled one), the moment it is placed.
  #
  # Pace: today up to this minute against the same weekday last week up to the
  # same minute of its business day, so a slow afternoon shows as a drop while
  # there is still time to act on it. Last week's orders are long completed, so
  # the same filter covers both days.
  #
  # Sales = order total less the driver's delivery fee less refunds, the same
  # figure the dashboard used for completed orders.
  class LiveSalesService
    COUNTED_STATUSES = (Order::PLACED_STATUSES + %w[completed]).freeze

    Result = Struct.new(
      :business_date, :now, :sales_cents, :order_count, :avg_cents, :collected_cents,
      :last_week_date, :last_week_same_time_cents, :last_week_same_time_count, :last_week_full_day_cents,
      :change_percent, :by_branch, :by_hour, keyword_init: true
    )

    def self.call(...) = new(...).call

    # location_ids: nil means every branch (and orders with no branch).
    def initialize(location_ids: nil, now: Time.current)
      @location_ids = location_ids
      @now = now
    end

    def call
      date = BusinessDay.clock_today
      today_range = BusinessDay.range(date)
      elapsed = @now - today_range.begin
      last_week_date = date - 7
      last_week_range = BusinessDay.range(last_week_date)
      last_week_so_far = last_week_range.begin...(last_week_range.begin + elapsed)

      today = rows(today_range.begin...@now)
      last_week = rows(last_week_range)
      last_week_so_far_rows = last_week.select { |r| last_week_so_far.cover?(r[:created_at]) }

      sales = sum(today)
      before = sum(last_week_so_far_rows)

      Result.new(
        business_date: date,
        now: @now,
        sales_cents: sales,
        order_count: today.size,
        avg_cents: today.empty? ? 0 : sales / today.size,
        collected_cents: collected(today.map { |r| r[:id] }),
        last_week_date: last_week_date,
        last_week_same_time_cents: before,
        last_week_same_time_count: last_week_so_far_rows.size,
        last_week_full_day_cents: sum(last_week),
        change_percent: before.positive? ? ((sales - before) * 100.0 / before).round : nil,
        by_branch: by_branch(today, last_week_so_far_rows),
        by_hour: by_hour(today, last_week, today_range.begin, last_week_range.begin)
      )
    end

    private

    # One hash per order: when, which branch, and its sales net of refunds.
    def rows(range)
      scope = Order.where(status: COUNTED_STATUSES, created_at: range)
      scope = scope.where(location_id: @location_ids) unless @location_ids.nil?
      orders = scope.pluck(:id, :created_at, :location_id, Arel.sql("orders.total_cents - orders.delivery_fee_cents"))
      refunds = refunds_by_order(orders.map(&:first))
      orders.map do |id, created_at, location_id, cents|
        { id: id, created_at: created_at, location_id: location_id, cents: cents.to_i - refunds.fetch(id, 0) }
      end
    end

    def refunds_by_order(ids)
      return {} if ids.empty?

      Payment.where(order_id: ids, status: %w[refunded partially_refunded])
        .group(:order_id).sum(:refunded_amount_cents)
    end

    # Money actually taken for today's orders (payments less what was refunded).
    def collected(ids)
      return 0 if ids.empty?

      Payment.where(order_id: ids, status: Order::SETTLING_PAYMENT_STATUSES)
        .sum(Arel.sql("payments.amount_cents - payments.refunded_amount_cents")).to_i
    end

    def sum(rows) = rows.sum { |r| r[:cents] }

    # Each branch with sales today: today so far vs last week at the same time.
    def by_branch(today, last_week_so_far)
      ids = (today + last_week_so_far).map { |r| r[:location_id] }.uniq
      return [] if ids.size < 2 # one branch: the headline already says it all

      names = Location.where(id: ids.compact).pluck(:id, :name).to_h
      ids.map do |id|
        now_rows = today.select { |r| r[:location_id] == id }
        before = sum(last_week_so_far.select { |r| r[:location_id] == id })
        sales = sum(now_rows)
        {
          location_id: id,
          name: names[id],
          sales_cents: sales,
          order_count: now_rows.size,
          last_week_cents: before,
          change_percent: before.positive? ? ((sales - before) * 100.0 / before).round : nil
        }
      end.sort_by { |b| -b[:sales_cents] }
    end

    # Sales per hour of the business day, today (up to now) and all of last week's
    # same day, keyed "HH:00" in business-day order (06:00 → 05:00).
    def by_hour(today, last_week, today_start, last_week_start)
      bucket = ->(rows, start) {
        rows.group_by { |r| ((r[:created_at] - start) / 3600).floor }.transform_values { |rs| sum(rs) }
      }
      today_hours = bucket.call(today, today_start)
      last_week_hours = bucket.call(last_week, last_week_start)
      current_hour = ((@now - today_start) / 3600).floor

      (0..23).map do |i|
        label = (today_start + i.hours).strftime("%H:00")
        {
          hour: label,
          today_cents: i <= current_hour ? today_hours.fetch(i, 0) : nil,
          last_week_cents: last_week_hours.fetch(i, 0)
        }
      end
    end
  end
end
