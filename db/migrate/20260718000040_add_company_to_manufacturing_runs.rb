# frozen_string_literal: true

# Scope manufacturing runs to a company (tenant). Backfill from each run's
# template, which is already company-scoped.
class AddCompanyToManufacturingRuns < ActiveRecord::Migration[7.1]
  def up
    add_column :manufacturing_runs, :company_id, :uuid

    execute <<~SQL.squish
      UPDATE manufacturing_runs SET company_id = mt.company_id
      FROM manufacturing_templates mt
      WHERE mt.id = manufacturing_runs.manufacturing_template_id
    SQL

    change_column_null :manufacturing_runs, :company_id, false
    add_index :manufacturing_runs, :company_id
    add_foreign_key :manufacturing_runs, :companies
  end

  def down
    remove_foreign_key :manufacturing_runs, :companies
    remove_column :manufacturing_runs, :company_id
  end
end
