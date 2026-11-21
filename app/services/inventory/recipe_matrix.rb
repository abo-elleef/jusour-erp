# frozen_string_literal: true

module Inventory
  # The recipe matrix of one menu item: a row per combination of the options in
  # the groups ticked as "changes the recipe", each showing what that
  # combination uses (from LineConsumption, so exactly what stock deduction
  # takes). A row with a saved CombinationRecipe is "custom"; any other row is
  # "auto" — the item recipe plus the options' own recipes — and is also the
  # starting point when the owner customises it.
  class RecipeMatrix
    # Past this many rows a matrix stops being something an owner can check.
    MANY_ROWS = 30

    Choice = Data.define(:group, :modifier) do
      def label
        modifier ? modifier.name : I18n.t("menu.recipe_matrix.no_choice", group: group.name)
      end
    end

    # changes: for a custom row, how it differs from the automatic recipe —
    # { ingredient => { kind: :changed / :added, from: automatic quantity } } —
    # and removed: the ingredients it dropped.
    Row = Data.define(:choices, :key, :combination, :quantities, :cost_cents, :changes, :removed) do
      def custom? = combination.present?

      def change_for(ingredient) = changes[ingredient]

      def label = choices.map(&:label).join(" · ")
    end

    attr_reader :menu_item

    def initialize(menu_item)
      @menu_item = MenuItem.includes(
        recipes: [:unit_ref, { ingredient: [:unit_ref, :ingredient_units] }],
        menu_item_modifier_groups: { modifier_group: { modifiers: { modifier_recipes:
          [:unit_ref, { ingredient: [:unit_ref, :ingredient_units] }] } } },
        combination_recipes: { lines: [:unit_ref, { ingredient: [:unit_ref, :ingredient_units] }] }
      ).find(menu_item.id)
    end

    # Every group on the item, with whether it is ticked and whether it can be.
    def attachments
      @menu_item.menu_item_modifier_groups
    end

    def groups
      @groups ||= attachments.select(&:recipe_matrix).map(&:modifier_group)
    end

    def rows
      @rows ||= combinations.map { |choices| row_for(choices) }
    end

    def many_rows?
      rows.size > MANY_ROWS
    end

    def row_for_key(key)
      rows.find { |row| row.key == CombinationRecipe.key_for(key) }
    end

    # The add-up result for a combination: the starting point of a custom row,
    # netted per ingredient, in base units, dropping anything that nets to zero.
    def starting_quantities(modifiers)
      LineConsumption.new(@menu_item, modifiers, use_matrix: false).lines
        .each_with_object(Hash.new(0)) { |line, totals| totals[line.ingredient] += line.base_quantity }
        .select { |_ingredient, quantity| quantity.positive? }
    end

    private

    def combinations
      return [] if groups.empty?

      first, *rest = groups.map { |group| choices_for(group) }
      first.product(*rest)
    end

    def choices_for(group)
      choices = group.modifiers.map { |modifier| Choice.new(group: group, modifier: modifier) }
      choices.unshift(Choice.new(group: group, modifier: nil)) unless group.required
      choices
    end

    def row_for(choices)
      modifiers = choices.filter_map(&:modifier)
      consumption = LineConsumption.new(@menu_item, modifiers)
      lines = consumption.lines
      quantities = lines.each_with_object(Hash.new(0)) { |line, totals| totals[line.ingredient] += line.base_quantity }
      changes, removed = consumption.combination ? differences(quantities, modifiers) : [{}, []]
      Row.new(
        choices: choices,
        key: CombinationRecipe.key_for(modifiers.map(&:id)),
        combination: consumption.combination,
        quantities: quantities.reject { |_ingredient, quantity| quantity.zero? }.sort_by { |ingredient, _| ingredient.name },
        cost_cents: lines.sum(&:cost_cents),
        changes: changes,
        removed: removed
      )
    end

    # What the owner changed in a custom row compared with the automatic recipe.
    def differences(quantities, modifiers)
      auto = starting_quantities(modifiers)
      changes = quantities.each_with_object({}) do |(ingredient, quantity), out|
        if !auto.key?(ingredient) then out[ingredient] = { kind: :added, from: nil }
        elsif auto[ingredient].round(4) != quantity.round(4) then out[ingredient] = { kind: :changed, from: auto[ingredient] }
        end
      end
      removed = auto.keys.reject { |ingredient| quantities[ingredient].to_d.positive? }.sort_by(&:name)
      [changes, removed]
    end
  end
end
