# frozen_string_literal: true

# Manufactured ingredients (manufacturing template outputs) can have their
# cost_per_unit_cents derived from the weighted average of their own remaining
# stock batches, rather than typed by hand. `cost_source` gates that: the sync
# only ever touches rows marked "derived", so a cost someone set deliberately is
# never stomped.
#
# The backfill flips only outputs sitting at zero cost — those contribute nothing
# to the valuation report today and have no value to lose. Outputs carrying a
# hand-entered cost stay "manual" until someone switches them over in the UI,
# having seen the stored and computed figures side by side.
class AddCostSourceToIngredients < ActiveRecord::Migration[7.1]
  def up
    add_column :ingredients, :cost_source, :string, null: false, default: "manual"
    add_column :ingredients, :cost_synced_at, :datetime

    execute <<~SQL
      UPDATE ingredients
      SET cost_source = 'derived'
      WHERE cost_per_unit_cents = 0
        AND id IN (SELECT DISTINCT output_ingredient_id FROM manufacturing_templates)
    SQL
  end

  def down
    remove_column :ingredients, :cost_synced_at
    remove_column :ingredients, :cost_source
  end
end
