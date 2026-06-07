# frozen_string_literal: true

class AddHappenedAtToPayrollAdjustments < ActiveRecord::Migration[7.1]
  def up
    add_column :payroll_adjustments, :happened_at, :date

    execute <<~SQL.squish
      UPDATE payroll_adjustments
      SET happened_at = DATE(created_at)
      WHERE happened_at IS NULL
    SQL

    change_column_null :payroll_adjustments, :happened_at, false
  end

  def down
    remove_column :payroll_adjustments, :happened_at
  end
end
