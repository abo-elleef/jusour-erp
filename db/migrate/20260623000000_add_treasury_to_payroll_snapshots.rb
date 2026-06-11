# frozen_string_literal: true

class AddTreasuryToPayrollSnapshots < ActiveRecord::Migration[7.1]
  def change
    add_reference :payroll_snapshots, :treasury, foreign_key: true, type: :uuid
    add_column :payroll_snapshots, :paid_on, :date
  end
end
