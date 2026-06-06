# frozen_string_literal: true

class AddOvertimeHoursToPayrollAdjustments < ActiveRecord::Migration[7.1]
  def change
    add_column :payroll_adjustments, :overtime_hours, :decimal, precision: 8, scale: 2
  end
end
