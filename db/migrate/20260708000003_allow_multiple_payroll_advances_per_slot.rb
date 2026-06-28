# frozen_string_literal: true

class AllowMultiplePayrollAdvancesPerSlot < ActiveRecord::Migration[7.1]
  def change
    remove_index :payroll_advances, name: "index_payroll_advances_on_user_month_and_slot"
  end
end
