# frozen_string_literal: true

module Accounting
  # The notes cashiers typed on POS orders, for a date range and branch, read
  # from the same orders the Sales report counts (SalesReportService.orders_scope).
  #
  # Two kinds:
  #   item  — order_items.notes, the kitchen note on one line
  #   order — orders.notes, the note on the whole order
  #
  # Filters narrow by what was sold: a category, an item (menu item or combo),
  # and a modifier choice of that item. An item note matches when its own line
  # does; an order note matches when its order has at least one such line.
  #
  # Keys (also used by the Sales report to link its rows here):
  #   item_key     "m:<menu_item_id>" or "c:<combo_id>"
  #   category_key "<category_id>" or "combos"
  # Modifier groups and choices are matched by *name*, as the Sales report's
  # modifier breakdown does, so a group duplicated per item reads as one.
  class OrderNotesService
    KINDS = %w[item order].freeze
    COMBOS = "combos"
    PRESENT = "btrim(COALESCE(%s, '')) <> ''"

    def self.item_key(menu_item_id, combo_id)
      combo_id ? "c:#{combo_id}" : "m:#{menu_item_id}"
    end

    def self.category_key(category_id, combo_id)
      combo_id ? COMBOS : category_id
    end

    def initialize(start_date, end_date, include_open: false, location_id: nil,
                   category: nil, item: nil, modifier_group: nil, modifier_choice: nil,
                   kind: nil, query: nil)
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @include_open = include_open
      @location_id = location_id
      @category = category.presence
      @item = item.presence
      @modifier_group = modifier_group.presence
      @modifier_choice = modifier_choice.presence
      @kind = KINDS.include?(kind) ? kind : nil
      @query = query.to_s.strip.presence
    end

    # Every matching note, newest first. Each row:
    #   kind, text, order, item_name, category, modifiers (names), quantity
    def notes
      rows = []
      rows.concat(item_note_rows) unless @kind == "order"
      rows.concat(order_note_rows) unless @kind == "item"
      rows.sort_by { |r| [-(r[:order].placed_at || r[:order].created_at).to_f, r[:order].order_number.to_s, r[:kind] == :order ? 0 : 1] }
    end

    # How many notes the page shows for each Sales report row (no filters of
    # this service apply — it counts for every row at once):
    #   { total:, categories: { key => n }, items: { item_key => n },
    #     choices: { [item_key, group, choice] => n } }
    # A row's count = its item notes + the order notes of orders that have it.
    def counts
      category_sql = "CASE WHEN order_items.combo_id IS NOT NULL THEN '#{COMBOS}' ELSE menu_items.category_id::text END"
      item_sql = "CASE WHEN order_items.combo_id IS NOT NULL THEN 'c:' || order_items.combo_id::text ELSE 'm:' || order_items.menu_item_id::text END"

      lines = OrderItem.joins(:order)
        .joins("LEFT JOIN menu_items ON menu_items.id = order_items.menu_item_id")
        .where(order_id: orders.select(:id))
      choice_lines = lines.joins(order_item_modifiers: { modifier: :modifier_group })

      {
        total: total_count,
        categories: tally(lines, [category_sql]).transform_keys(&:first),
        items: tally(lines, [item_sql]).transform_keys(&:first),
        choices: tally(choice_lines, [item_sql, "modifier_groups.name", "order_item_modifiers.name"])
      }
    end

    # Items sold in the range, for the item filter: [[label, item_key]].
    def item_options
      OrderItem.where(order_id: orders.select(:id))
        .joins("LEFT JOIN menu_items ON menu_items.id = order_items.menu_item_id")
        .joins("LEFT JOIN combos ON combos.id = order_items.combo_id")
        .distinct
        .pluck(Arel.sql("COALESCE(menu_items.name, combos.name)"), :menu_item_id, :combo_id)
        .map { |name, menu_item_id, combo_id| [name, self.class.item_key(menu_item_id, combo_id)] }
        .sort_by { |name, _| name.to_s.downcase }
    end

    # The chosen item's modifier choices sold in the range: [[group, choice]].
    def choice_options
      return [] unless @item

      item_filter(OrderItem.where(order_id: orders.select(:id)))
        .joins(order_item_modifiers: { modifier: :modifier_group })
        .distinct
        .pluck("modifier_groups.name", "order_item_modifiers.name")
        .sort_by { |g, c| [g.to_s, c.to_s] }
    end

    private

    def orders
      @orders ||= SalesReportService.orders_scope(@start_date, @end_date, include_open: @include_open, location_id: @location_id)
    end

    def line_filter?
      @category || @item || (@modifier_group && @modifier_choice)
    end

    # OrderItem scope narrowed by the category / item / choice filters.
    def lines
      scope = OrderItem.where(order_id: orders.select(:id))
      scope = category_filter(scope)
      scope = item_filter(scope)
      choice_filter(scope)
    end

    def category_filter(scope)
      return scope unless @category
      return scope.where.not(combo_id: nil) if @category == COMBOS

      scope.where(combo_id: nil, menu_item_id: MenuItem.where(category_id: @category).select(:id))
    end

    def item_filter(scope)
      return scope unless @item

      type, id = @item.split(":", 2)
      case type
      when "m" then scope.where(menu_item_id: id, combo_id: nil)
      when "c" then scope.where(combo_id: id)
      else scope.none
      end
    end

    def choice_filter(scope)
      return scope unless @modifier_group && @modifier_choice

      with_choice = OrderItemModifier.joins(modifier: :modifier_group)
        .where(modifier_groups: { name: @modifier_group }, name: @modifier_choice)
        .select(:order_item_id)
      scope.where(id: with_choice)
    end

    def search(scope, column)
      return scope unless @query

      scope.where("#{column} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
    end

    def item_note_rows
      scope = lines.where(format(PRESENT, "order_items.notes"))
      search(scope, "order_items.notes")
        .includes({ order: %i[location user] }, { menu_item: :category }, :combo, :order_item_modifiers)
        .map do |line|
          {
            kind: :item,
            text: line.notes.strip,
            order: line.order,
            item_name: line.menu_item&.name || line.combo&.name,
            category: line.combo ? I18n.t("accounting.sales_reports.combos_category") : line.menu_item&.category&.name,
            modifiers: line.order_item_modifiers.map(&:name),
            quantity: line.quantity
          }
        end
    end

    def order_note_rows
      scope = orders.where(format(PRESENT, "orders.notes"))
      scope = scope.where(id: lines.select(:order_id)) if line_filter?
      search(scope, "orders.notes").includes(:location, :user).map do |order|
        { kind: :order, text: order.notes.strip, order: order, item_name: nil, category: nil, modifiers: [], quantity: nil }
      end
    end

    def total_count
      item = OrderItem.where(order_id: orders.select(:id)).where(format(PRESENT, "order_items.notes")).count
      order = orders.where(format(PRESENT, "orders.notes")).count
      item + order
    end

    # Per group key: item notes on matching lines + distinct orders (with an
    # order note) that have a matching line.
    def tally(scope, key_sqls)
      keys = key_sqls.map { |s| Arel.sql(s) }
      item_notes = scope.where(format(PRESENT, "order_items.notes"))
        .group(*keys).distinct.count("order_items.id")
      order_notes = scope.where(format(PRESENT, "orders.notes"))
        .group(*keys).distinct.count("orders.id")
      normalize(item_notes).merge(normalize(order_notes)) { |_, a, b| a + b }
    end

    # group(...).count gives a scalar key for one column; make it always an array.
    def normalize(hash)
      hash.transform_keys { |k| Array(k) }
    end
  end
end
