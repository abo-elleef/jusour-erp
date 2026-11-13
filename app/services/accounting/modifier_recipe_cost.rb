# frozen_string_literal: true

module Accounting
  # What the modifiers chosen on order lines cost in ingredients: each chosen
  # modifier's recipe, at the ingredient's standard cost, times the line's
  # quantity. A "Double" that adds a second patty costs that patty here.
  #
  # Stock deduction (Inventory::DeductStockService) already draws these
  # ingredients down; this keeps the cost figures (food cost, daily COGS) in step
  # with it. Like that service it skips combo lines (no menu_item_id). Quantities
  # are converted from the recipe's unit to the ingredient's base unit, and are
  # signed, so a "without X" modifier with a negative recipe lowers the cost.
  # Rounded per recipe line, the way an item's own recipe cost is.
  module ModifierRecipeCost
    COST_SQL = <<~SQL.squish.freeze
      ROUND(#{Inventory::BaseQuantitySql.for("modifier_recipes", "quantity")} * ingredients.cost_per_unit_cents) * order_items.quantity
    SQL

    module_function

    # { menu_item_id => cents } over the given order lines.
    def by_menu_item(order_items)
      order_items
        .where.not(menu_item_id: nil)
        .joins(order_item_modifiers: { modifier: { modifier_recipes: :ingredient } })
        .group("order_items.menu_item_id")
        .sum(Arel.sql(COST_SQL))
        .transform_values { |cents| cents.to_i }
    end
  end
end
