# frozen_string_literal: true

module Inventory
  # What one unit of a sold line uses: the menu item's own recipe plus the
  # recipes of the modifiers chosen on it, each quantity in the ingredient's
  # base unit. The single place this is worked out — stock deduction, the void
  # restock, daily COGS, the food cost report and theoretical usage all read it,
  # so none of them can disagree.
  #
  # Each line keeps its own source row (an ingredient can come from the item
  # and from a modifier), and its cost is rounded per source row, per unit, the
  # way the cost figures always have been.
  class LineConsumption
    Line = Data.define(:ingredient, :base_quantity, :cost_cents, :source)

    def self.call(menu_item:, modifiers:)
      new(menu_item, modifiers).lines
    end

    # { ingredient => base quantity } for `units` of the line, netted per ingredient.
    def self.totals(menu_item:, modifiers:, units: 1)
      call(menu_item: menu_item, modifiers: modifiers).each_with_object(Hash.new(0)) do |line, totals|
        totals[line.ingredient] += line.base_quantity * units
      end
    end

    def initialize(menu_item, modifiers)
      @menu_item = menu_item
      @modifiers = modifiers.to_a
    end

    def lines
      item_lines + modifier_lines
    end

    private

    def item_lines
      @menu_item.recipes.map { |recipe| build(recipe.ingredient, recipe.base_quantity_used, recipe) }
    end

    def modifier_lines
      @modifiers.flat_map do |modifier|
        modifier.modifier_recipes.map { |mr| build(mr.ingredient, mr.base_quantity, mr) }
      end
    end

    def build(ingredient, base_quantity, source)
      Line.new(
        ingredient: ingredient,
        base_quantity: base_quantity,
        cost_cents: (base_quantity * ingredient.cost_per_unit_cents).round,
        source: source
      )
    end
  end
end
