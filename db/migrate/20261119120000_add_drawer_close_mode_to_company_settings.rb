# frozen_string_literal: true

# How a drawer close books an over/short count: "documented" (today's
# behaviour — income for over, voucher to the cashier for short) or "simple"
# (the counted cash goes to the treasury, the gap is only reported).
class AddDrawerCloseModeToCompanySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :company_settings, :drawer_close_mode, :string, default: "documented", null: false
  end
end
