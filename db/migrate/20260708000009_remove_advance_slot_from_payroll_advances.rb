# frozen_string_literal: true

class RemoveAdvanceSlotFromPayrollAdvances < ActiveRecord::Migration[7.1]
  def change
    remove_column :payroll_advances, :advance_slot, :string, null: false
  end
end
