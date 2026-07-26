# frozen_string_literal: true

class AddBusinessDayStartHourToCompanySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :company_settings, :business_day_start_hour, :integer, default: 6, null: false
  end
end
