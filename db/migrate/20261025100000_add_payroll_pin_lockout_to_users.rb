# frozen_string_literal: true

# The staff payroll link is protected by a 4-digit PIN. Count wrong guesses
# per employee and lock the link for a while after too many.
class AddPayrollPinLockoutToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :payroll_pin_failed_attempts, :integer, null: false, default: 0
    add_column :users, :payroll_pin_locked_until, :datetime
  end
end
