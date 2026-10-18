class AddBalanceDeductionToPayroll < ActiveRecord::Migration[7.1]
  # users.balance_deduction_cents — a standing "take X a month off what they
  # owe" plan for an employee who was paid well ahead of their salary (a large
  # advance repaid over several months). Blank means the old behaviour: the
  # whole month's pay goes to what they owe until it's cleared.
  #
  # payroll_snapshots.deduction_cents — how much of the month's pay was
  # actually kept back against what they owed when the month was finalized.
  def change
    add_column :users, :balance_deduction_cents, :integer
    add_column :payroll_snapshots, :deduction_cents, :integer, default: 0, null: false
  end
end
