# frozen_string_literal: true

module Inventory
  # SQL for a recipe row's quantity in its ingredient's base unit — the
  # set-based twin of Ingredient#to_base, for reports that sum over many lines.
  #
  # A row with no unit, or with the ingredient's base unit, is already in base.
  # Otherwise the ingredient's conversion row supplies the factor; a unit the
  # ingredient no longer has reads as base, as Recipe#base_quantity_used and
  # ModifierRecipe#base_quantity do in Ruby.
  module BaseQuantitySql
    module_function

    # BaseQuantitySql.for("recipes", "quantity_used")
    # BaseQuantitySql.for("modifier_recipes", "quantity")
    def for(table, quantity_column)
      <<~SQL.squish
        (#{table}.#{quantity_column} * CASE
          WHEN #{table}.unit_id IS NULL
            OR #{table}.unit_id = (SELECT base.unit_id FROM ingredients base WHERE base.id = #{table}.ingredient_id)
          THEN 1
          ELSE COALESCE(
            (SELECT iu.base_units_per_unit FROM ingredient_units iu
             WHERE iu.ingredient_id = #{table}.ingredient_id AND iu.unit_id = #{table}.unit_id
             LIMIT 1), 1)
        END)
      SQL
    end
  end
end
