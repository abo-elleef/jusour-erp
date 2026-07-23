# frozen_string_literal: true

# A human-readable, per-company yearly sequence for production runs, like
# vendor invoices (VI-) and journal entries (JE-). Format: MFG-<year>-NNNNN.
class AddRunNumberToManufacturingRuns < ActiveRecord::Migration[7.1]
  def up
    add_column :manufacturing_runs, :run_number, :string

    execute <<~SQL.squish
      UPDATE manufacturing_runs SET run_number = sub.rn FROM (
        SELECT id,
               'MFG-' || EXTRACT(YEAR FROM occurred_on)::int || '-' ||
               LPAD(
                 (ROW_NUMBER() OVER (
                    PARTITION BY company_id, EXTRACT(YEAR FROM occurred_on)
                    ORDER BY occurred_on, created_at, id
                 ))::text, 5, '0'
               ) AS rn
        FROM manufacturing_runs
      ) sub
      WHERE manufacturing_runs.id = sub.id
    SQL

    change_column_null :manufacturing_runs, :run_number, false
    add_index :manufacturing_runs, %i[company_id run_number], unique: true
  end

  def down
    remove_index :manufacturing_runs, %i[company_id run_number]
    remove_column :manufacturing_runs, :run_number
  end
end
