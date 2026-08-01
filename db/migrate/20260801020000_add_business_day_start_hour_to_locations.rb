# frozen_string_literal: true

class AddBusinessDayStartHourToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :business_day_start_hour, :integer
  end
end
