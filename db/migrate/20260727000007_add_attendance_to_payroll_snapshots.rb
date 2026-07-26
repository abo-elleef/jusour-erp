# frozen_string_literal: true

# Freeze the attendance-derived figures alongside the rest of a finalized
# payroll snapshot, so a finalized month stays auditable even if attendance
# is edited afterwards.
class AddAttendanceToPayrollSnapshots < ActiveRecord::Migration[7.1]
  def change
    add_column :payroll_snapshots, :attendance_pay_cents, :integer, null: false, default: 0
    add_column :payroll_snapshots, :payable_days, :decimal, precision: 6, scale: 2, null: false, default: "0.0"
    add_column :payroll_snapshots, :bonus_days, :decimal, precision: 6, scale: 2, null: false, default: "0.0"
    add_column :payroll_snapshots, :penalty_days, :decimal, precision: 6, scale: 2, null: false, default: "0.0"
  end
end
