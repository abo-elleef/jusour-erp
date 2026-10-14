class AddWagesAccountCodeToUsers < ActiveRecord::Migration[7.1]
  # Self-contained on purpose (raw SQL, no app models) — see
  # feedback_migrations_no_app_models. Every existing user gets a code now,
  # ordered by name within their company, exactly how Treasury/Loan/Partner
  # were backfilled before this; a new user gets one on create via
  # User#assign_wages_account_code, the same +1-off-the-max pattern.
  #
  # Base 6000 is a clean, currently-unused block: ExpenseCategory grows
  # upward from 5000 and the fixed payroll/purchases/interest codes
  # (5100/5500-5503/5600) already live in that decade, so per-employee codes
  # get their own space instead of racing that growth.
  def up
    add_column :users, :wages_account_code, :integer, if_not_exists: true

    execute <<~SQL.squish
      WITH ordered AS (
        SELECT id, 6000 AS base,
               ROW_NUMBER() OVER (PARTITION BY company_id ORDER BY name) AS ordinal
        FROM users
      )
      UPDATE users SET wages_account_code = ordered.base + ordered.ordinal
      FROM ordered WHERE users.id = ordered.id
    SQL

    change_column_null :users, :wages_account_code, false
    add_index :users, %i[company_id wages_account_code], unique: true
  end

  def down
    remove_index :users, %i[company_id wages_account_code]
    remove_column :users, :wages_account_code
  end
end
