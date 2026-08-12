# frozen_string_literal: true

class AddMainIngredientControlToManufacturing < ActiveRecord::Migration[7.1]
  def change
    # How a template's run size is driven: "runs" (enter a run count, current
    # behaviour) or "main_ingredient" (enter the actual amount of a designated
    # input and let the recipe ratio scale everything else).
    add_column :manufacturing_templates, :control_mode, :string, null: false, default: "runs"
    add_reference :manufacturing_templates, :main_ingredient,
      type: :uuid, null: true, foreign_key: { to_table: :ingredients }

    # What the operator entered for a main-ingredient-controlled run (audit trail;
    # runs_count still stores the derived multiplier the engine applied).
    add_column :manufacturing_runs, :main_input_quantity, :decimal, precision: 10, scale: 3, null: true
    add_reference :manufacturing_runs, :main_input_unit,
      type: :uuid, null: true, foreign_key: { to_table: :units }
  end
end
