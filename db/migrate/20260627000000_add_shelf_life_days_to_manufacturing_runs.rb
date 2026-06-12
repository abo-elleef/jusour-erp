# frozen_string_literal: true

class AddShelfLifeDaysToManufacturingRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :manufacturing_runs, :shelf_life_days, :integer, null: false, default: 7
    change_column_default :manufacturing_runs, :shelf_life_days, from: 7, to: nil
  end
end
