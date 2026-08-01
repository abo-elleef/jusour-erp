# frozen_string_literal: true

class AddBusinessDayModeToLocations < ActiveRecord::Migration[7.1]
  def up
    add_column :locations, :business_day_mode, :string, null: false, default: "automatic"

    say_with_time "Backfill locations.business_day_mode from company_settings" do
      execute <<~SQL.squish
        UPDATE locations
        SET business_day_mode = COALESCE(
          (
            SELECT cs.business_day_mode
            FROM company_settings cs
            WHERE cs.company_id = locations.company_id
            LIMIT 1
          ),
          'automatic'
        )
        WHERE location_type = 'branch'
      SQL
    end
  end

  def down
    remove_column :locations, :business_day_mode
  end
end
