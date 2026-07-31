# frozen_string_literal: true

# Shift clock-out used to auto-create Labor expenses (hours × rate). Pay is now
# monthly salary from attendance, so those accruals double-count labor and are removed.
class RemoveAutoShiftLaborExpenses < ActiveRecord::Migration[7.1]
  def up
    Expense.unscoped
      .where(is_auto_generated: true, source_record_type: "ShiftLog")
      .find_each(&:destroy!)
  end

  def down
    # Irreversible: auto shift labor expenses are no longer created.
  end
end
