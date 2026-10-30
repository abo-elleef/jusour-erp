# frozen_string_literal: true

# What one base unit of the movement was worth when it happened, so valued
# inventory reports keep a stable history instead of re-pricing the past at
# today's cost. Nullable because history is filled by
# inventory:backfill_movement_costs, not here; rows that task can only estimate
# are flagged so reports can say so.
class AddUnitCostToStockAdjustments < ActiveRecord::Migration[7.1]
  def change
    add_column :stock_adjustments, :unit_cost_cents, :integer
    add_column :stock_adjustments, :unit_cost_estimated, :boolean, default: false, null: false
  end
end
