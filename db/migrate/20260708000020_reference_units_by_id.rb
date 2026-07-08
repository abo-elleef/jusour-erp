# frozen_string_literal: true

# Replace the string `unit` columns with FK references to `units`. Backfill by
# matching each stored name to the company's seeded unit, then drop the strings.
# Company scoping is done via each row's ingredient (or the row's own company).
class ReferenceUnitsById < ActiveRecord::Migration[7.1]
  def up
    add_reference :ingredients, :unit, type: :uuid, index: true, foreign_key: true
    add_reference :ingredient_units, :unit, type: :uuid, index: true, foreign_key: true
    add_reference :recipes, :unit, type: :uuid, index: true, foreign_key: true
    add_reference :manufacturing_template_lines, :unit, type: :uuid, index: true, foreign_key: true
    add_reference :stock_transfer_lines, :unit, type: :uuid, index: true, foreign_key: true
    add_reference :stock_adjustments, :unit, type: :uuid, index: true, foreign_key: true
    add_reference :vendor_invoice_lines, :unit, type: :uuid, index: true, foreign_key: true
    add_reference :stock_take_items, :counted_unit, type: :uuid, index: true, foreign_key: { to_table: :units }
    add_reference :manufacturing_templates, :yield_unit, type: :uuid, index: true, foreign_key: { to_table: :units }

    # --- Backfill ---
    execute <<~SQL.squish
      UPDATE ingredients SET unit_id = u.id FROM units u
      WHERE u.company_id = ingredients.company_id AND LOWER(u.name) = LOWER(ingredients.unit)
    SQL
    execute <<~SQL.squish
      UPDATE ingredient_units SET unit_id = u.id FROM units u
      WHERE u.company_id = ingredient_units.company_id AND LOWER(u.name) = LOWER(ingredient_units.unit)
    SQL
    backfill_via_ingredient("recipes", "unit", "unit_id")
    backfill_via_ingredient("manufacturing_template_lines", "unit", "unit_id")
    backfill_via_ingredient("stock_transfer_lines", "unit", "unit_id")
    backfill_via_ingredient("stock_adjustments", "unit", "unit_id")
    backfill_via_ingredient("vendor_invoice_lines", "unit", "unit_id")
    backfill_via_ingredient("stock_take_items", "counted_unit", "counted_unit_id")
    execute <<~SQL.squish
      UPDATE manufacturing_templates SET yield_unit_id = u.id FROM units u
      WHERE u.company_id = manufacturing_templates.company_id
        AND manufacturing_templates.yield_unit IS NOT NULL
        AND LOWER(u.name) = LOWER(manufacturing_templates.yield_unit)
    SQL

    change_column_null :ingredients, :unit_id, false
    change_column_null :ingredient_units, :unit_id, false

    remove_column :ingredients, :unit
    remove_column :ingredient_units, :unit
    remove_column :recipes, :unit
    remove_column :manufacturing_template_lines, :unit
    remove_column :stock_transfer_lines, :unit
    remove_column :stock_adjustments, :unit
    remove_column :vendor_invoice_lines, :unit
    remove_column :stock_take_items, :counted_unit
    remove_column :manufacturing_templates, :yield_unit
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Rows without a company_id of their own are scoped via their ingredient.
  def backfill_via_ingredient(table, string_col, id_col)
    execute <<~SQL.squish
      UPDATE #{table} SET #{id_col} = u.id
      FROM ingredients i, units u
      WHERE i.id = #{table}.ingredient_id
        AND u.company_id = i.company_id
        AND #{table}.#{string_col} IS NOT NULL
        AND LOWER(u.name) = LOWER(#{table}.#{string_col})
    SQL
  end
end
