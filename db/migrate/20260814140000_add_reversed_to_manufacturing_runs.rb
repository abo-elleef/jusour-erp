# frozen_string_literal: true

class AddReversedToManufacturingRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :manufacturing_runs, :reversed_at, :datetime
    add_reference :manufacturing_runs, :reversed_by, type: :uuid, foreign_key: { to_table: :users }, null: true
    add_index :manufacturing_runs, :reversed_at
  end
end
