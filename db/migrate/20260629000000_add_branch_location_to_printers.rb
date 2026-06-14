# frozen_string_literal: true

class AddBranchLocationToPrinters < ActiveRecord::Migration[7.1]
  def up
    rename_column :printers, :location, :station
    add_reference :printers, :location, type: :uuid, foreign_key: true, index: true

    execute <<~SQL.squish
      UPDATE printers
      SET location_id = (
        SELECT locations.id
        FROM locations
        WHERE locations.company_id = printers.company_id
          AND locations.active = TRUE
        ORDER BY
          CASE WHEN locations.location_type = 'branch' THEN 0 ELSE 1 END,
          locations.position,
          locations.name
        LIMIT 1
      )
      WHERE location_id IS NULL
    SQL
  end

  def down
    remove_reference :printers, :location, type: :uuid, foreign_key: true
    rename_column :printers, :station, :location
  end
end
