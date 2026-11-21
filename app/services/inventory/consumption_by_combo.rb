# frozen_string_literal: true

module Inventory
  # Consumption and recipe cost over many order lines, for the reports. Lines
  # are grouped by what decides their recipe — the menu item and the modifiers
  # chosen on it — so LineConsumption runs once per distinct combination, not
  # once per line. Combo lines (no menu_item_id) carry no recipe and are
  # skipped, as stock deduction skips them.
  class ConsumptionByCombo
    def initialize(order_items)
      @order_items = order_items
    end

    # { menu_item_id => cents } — what the lines cost in ingredients at standard cost.
    def cost_cents_by_menu_item
      combos.each_with_object(Hash.new(0)) do |(menu_item_id, modifier_ids, units), totals|
        per_unit = lines_for(menu_item_id, modifier_ids).sum(&:cost_cents)
        totals[menu_item_id] += (per_unit * units).round
      end
    end

    # { ingredient_id => base quantity } — what the lines should have used.
    def quantity_by_ingredient
      combos.each_with_object(Hash.new(0)) do |(menu_item_id, modifier_ids, units), totals|
        lines_for(menu_item_id, modifier_ids).each do |line|
          totals[line.ingredient.id] += line.base_quantity * units
        end
      end
    end

    private

    # [[menu_item_id, [modifier_id, ...], units], ...] — one row per distinct
    # combination. A modifier chosen twice on a line appears twice, so it counts twice.
    def combos
      @combos ||= begin
        per_line = @order_items.unscope(:order, :select)
          .where.not(menu_item_id: nil)
          .select(
            "order_items.menu_item_id",
            "order_items.quantity",
            "ARRAY(SELECT oim.modifier_id FROM order_item_modifiers oim " \
            "WHERE oim.order_item_id = order_items.id ORDER BY oim.modifier_id) AS modifier_ids"
          )
        sql = "SELECT menu_item_id, modifier_ids, SUM(quantity) FROM (#{per_line.to_sql}) lines " \
              "GROUP BY menu_item_id, modifier_ids"
        OrderItem.connection.select_rows(sql).map do |menu_item_id, modifier_ids, units|
          [menu_item_id, decode_array(modifier_ids), units.to_d]
        end
      end
    end

    def lines_for(menu_item_id, modifier_ids)
      @lines ||= {}
      @lines[[menu_item_id, modifier_ids]] ||= LineConsumption.call(
        menu_item: menu_items.fetch(menu_item_id),
        modifiers: modifier_ids.map { |id| modifiers.fetch(id) }
      )
    end

    # Not scoped to what is on sale now: a line sold earlier still cost what it cost.
    def menu_items
      @menu_items ||= MenuItem
        .where(id: combos.map(&:first).uniq)
        .includes(recipes: [:unit_ref, { ingredient: :ingredient_units }])
        .index_by(&:id)
    end

    def modifiers
      @modifiers ||= Modifier
        .where(id: combos.flat_map { |combo| combo[1] }.uniq)
        .includes(modifier_recipes: [:unit_ref, { ingredient: :ingredient_units }])
        .index_by(&:id)
    end

    def decode_array(value)
      return value if value.is_a?(Array)

      PG::TextDecoder::Array.new.decode(value)
    end
  end
end
