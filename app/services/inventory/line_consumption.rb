# frozen_string_literal: true

module Inventory
  # What one unit of a sold line uses, each quantity in the ingredient's base
  # unit. The single place this is worked out — stock deduction, the void
  # restock, daily COGS, the food cost report, theoretical usage and the recipe
  # matrix on the menu item page all read it, so none of them can disagree.
  #
  # Two ways a line is made up:
  # - matrix: the item has groups ticked as "changes the recipe" (size and
  #   spice, say) and the chosen options of those groups have a saved
  #   CombinationRecipe. That full recipe is used in place of the item recipe
  #   and those options' own recipes; options of other groups still add theirs.
  # - add-up (no matrix, or no saved row for this combination): the item recipe
  #   plus every chosen option's own recipe — also the starting guess the matrix
  #   offers for a row.
  #
  # Each line keeps its own source row, and its cost is rounded per source row,
  # per unit, the way the cost figures always have been.
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

    # use_matrix: false gives the add-up result even where a matrix row exists.
    def initialize(menu_item, modifiers, use_matrix: true)
      @menu_item = menu_item
      @modifiers = modifiers.to_a
      @use_matrix = use_matrix
    end

    def lines
      return add_up_lines unless combination

      combination.lines.map { |line| build(line.ingredient, line.base_quantity, line) } +
        option_lines(@modifiers.reject { |modifier| matrix_group_ids.include?(modifier.modifier_group_id) })
    end

    # The saved matrix row this line uses, or nil.
    def combination
      return @combination if defined?(@combination)

      @combination = if @use_matrix && matrix_group_ids.any?
        key = CombinationRecipe.key_for(
          @modifiers.select { |modifier| matrix_group_ids.include?(modifier.modifier_group_id) }.map(&:id)
        )
        @menu_item.combination_recipes.find { |recipe| recipe.modifier_ids == key }
      end
    end

    private

    def add_up_lines
      @menu_item.recipes.map { |recipe| build(recipe.ingredient, recipe.base_quantity_used, recipe) } +
        option_lines(@modifiers)
    end

    def option_lines(modifiers)
      modifiers.flat_map do |modifier|
        modifier.modifier_recipes.map { |mr| build(mr.ingredient, mr.base_quantity, mr) }
      end
    end

    def matrix_group_ids
      @matrix_group_ids ||= @menu_item.menu_item_modifier_groups.select(&:recipe_matrix).map(&:modifier_group_id)
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
