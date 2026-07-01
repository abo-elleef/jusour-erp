# frozen_string_literal: true

class AddStaffMealsCentsToPayrollSnapshots < ActiveRecord::Migration[7.1]
  def change
    add_column :payroll_snapshots, :staff_meals_cents, :integer, default: 0, null: false
  end
end
