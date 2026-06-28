# frozen_string_literal: true

class AddCompanyIdToTenantIsolatedTables < ActiveRecord::Migration[7.1]
  def up
    # ── expenses ────────────────────────────────────────────────────────────
    add_column :expenses, :company_id, :uuid
    execute <<~SQL
      UPDATE expenses
         SET company_id = users.company_id
        FROM users
       WHERE users.id = expenses.user_id
    SQL
    change_column_null :expenses, :company_id, false
    add_index :expenses, :company_id
    add_foreign_key :expenses, :companies

    # ── incomes ─────────────────────────────────────────────────────────────
    add_column :incomes, :company_id, :uuid
    execute <<~SQL
      UPDATE incomes
         SET company_id = users.company_id
        FROM users
       WHERE users.id = incomes.user_id
    SQL
    change_column_null :incomes, :company_id, false
    add_index :incomes, :company_id
    add_foreign_key :incomes, :companies

    # ── budgets ─────────────────────────────────────────────────────────────
    add_column :budgets, :company_id, :uuid
    execute <<~SQL
      UPDATE budgets
         SET company_id = expense_categories.company_id
        FROM expense_categories
       WHERE expense_categories.id = budgets.expense_category_id
    SQL
    change_column_null :budgets, :company_id, false
    add_index :budgets, :company_id
    add_foreign_key :budgets, :companies

    # ── shift_logs ──────────────────────────────────────────────────────────
    add_column :shift_logs, :company_id, :uuid
    execute <<~SQL
      UPDATE shift_logs
         SET company_id = users.company_id
        FROM users
       WHERE users.id = shift_logs.user_id
    SQL
    change_column_null :shift_logs, :company_id, false
    add_index :shift_logs, :company_id
    add_foreign_key :shift_logs, :companies

    # ── payroll_adjustments ─────────────────────────────────────────────────
    add_column :payroll_adjustments, :company_id, :uuid
    execute <<~SQL
      UPDATE payroll_adjustments
         SET company_id = users.company_id
        FROM users
       WHERE users.id = payroll_adjustments.user_id
    SQL
    change_column_null :payroll_adjustments, :company_id, false
    add_index :payroll_adjustments, :company_id
    add_foreign_key :payroll_adjustments, :companies

    # ── treasury_transactions ───────────────────────────────────────────────
    add_column :treasury_transactions, :company_id, :uuid
    execute <<~SQL
      UPDATE treasury_transactions
         SET company_id = treasuries.company_id
        FROM treasuries
       WHERE treasuries.id = treasury_transactions.treasury_id
    SQL
    change_column_null :treasury_transactions, :company_id, false
    add_index :treasury_transactions, :company_id
    add_foreign_key :treasury_transactions, :companies

    # ── treasury_transfers ──────────────────────────────────────────────────
    add_column :treasury_transfers, :company_id, :uuid
    execute <<~SQL
      UPDATE treasury_transfers
         SET company_id = treasuries.company_id
        FROM treasuries
       WHERE treasuries.id = treasury_transfers.from_treasury_id
    SQL
    change_column_null :treasury_transfers, :company_id, false
    add_index :treasury_transfers, :company_id
    add_foreign_key :treasury_transfers, :companies

    # ── payments ─────────────────────────────────────────────────────────────
    add_column :payments, :company_id, :uuid
    execute <<~SQL
      UPDATE payments
         SET company_id = orders.company_id
        FROM orders
       WHERE orders.id = payments.order_id
    SQL
    change_column_null :payments, :company_id, false
    add_index :payments, :company_id
    add_foreign_key :payments, :companies
  end

  def down
    remove_foreign_key :expenses, :companies
    remove_column :expenses, :company_id

    remove_foreign_key :incomes, :companies
    remove_column :incomes, :company_id

    remove_foreign_key :budgets, :companies
    remove_column :budgets, :company_id

    remove_foreign_key :shift_logs, :companies
    remove_column :shift_logs, :company_id

    remove_foreign_key :payroll_adjustments, :companies
    remove_column :payroll_adjustments, :company_id

    remove_foreign_key :treasury_transactions, :companies
    remove_column :treasury_transactions, :company_id

    remove_foreign_key :treasury_transfers, :companies
    remove_column :treasury_transfers, :company_id

    remove_foreign_key :payments, :companies
    remove_column :payments, :company_id
  end
end
