# frozen_string_literal: true

# Give income/expense categories a stable, stored account_code (like partners and
# loans already have) instead of computing it on the fly from a positional index.
# The old computed codes shifted with the date filter, the sort order, and
# add/delete of categories. Backfill by ORDER BY id to match the codes that the
# auto-posting service (account_for_*_category) already stamped onto existing
# journal-entry lines, so the ledger stays consistent.
class AddAccountCodeToCategories < ActiveRecord::Migration[7.1]
  def up
    add_column :income_categories, :account_code, :integer
    add_column :expense_categories, :account_code, :integer

    execute <<~SQL.squish
      UPDATE income_categories t SET account_code = s.code
      FROM (
        SELECT id, 4000 + ROW_NUMBER() OVER (PARTITION BY company_id ORDER BY id) AS code
        FROM income_categories
      ) s
      WHERE t.id = s.id
    SQL

    execute <<~SQL.squish
      UPDATE expense_categories t SET account_code = s.code
      FROM (
        SELECT id, 5000 + ROW_NUMBER() OVER (PARTITION BY company_id ORDER BY id) AS code
        FROM expense_categories
      ) s
      WHERE t.id = s.id
    SQL

    change_column_null :income_categories, :account_code, false
    change_column_null :expense_categories, :account_code, false
    add_index :income_categories, %i[company_id account_code], unique: true
    add_index :expense_categories, %i[company_id account_code], unique: true
  end

  def down
    remove_column :income_categories, :account_code
    remove_column :expense_categories, :account_code
  end
end
