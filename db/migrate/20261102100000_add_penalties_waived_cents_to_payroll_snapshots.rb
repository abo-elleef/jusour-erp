# frozen_string_literal: true

class AddPenaltiesWaivedCentsToPayrollSnapshots < ActiveRecord::Migration[7.1]
  def change
    add_column :payroll_snapshots, :penalties_waived_cents, :integer, default: 0, null: false
  end
end
