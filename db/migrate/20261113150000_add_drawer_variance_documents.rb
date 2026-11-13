# frozen_string_literal: true

# A drawer's over/short becomes a document instead of a number nobody can explain.
#
# The safe receives the cash the drawer should have held (expected), and the gap
# is booked on its own:
#   - over:  an Income in the branch's chosen category and treasury;
#   - short: a payment voucher to the cashier's staff account, as if they took it
#            from the safe — unless a manager waives it, which books an Expense.
#
# Drawers reconciled before this keep booking what was counted
# (variance_documented stays false), so reopening or correcting an old drawer
# re-posts it the way it was posted.
class AddDrawerVarianceDocuments < ActiveRecord::Migration[7.1]
  def change
    add_reference :locations, :cash_over_treasury, type: :uuid, foreign_key: { to_table: :treasuries }
    add_reference :locations, :cash_over_income_category, type: :uuid, foreign_key: { to_table: :income_categories }
    add_reference :locations, :cash_short_expense_category, type: :uuid, foreign_key: { to_table: :expense_categories }

    add_column :cash_drawer_sessions, :variance_documented, :boolean, default: false, null: false
    add_reference :cash_drawer_sessions, :shortage_voucher, type: :uuid, foreign_key: { to_table: :vouchers }
    add_column :cash_drawer_sessions, :shortage_waived_at, :datetime
    add_reference :cash_drawer_sessions, :shortage_waived_by, type: :uuid, foreign_key: { to_table: :users }
  end
end
