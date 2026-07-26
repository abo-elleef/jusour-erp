# frozen_string_literal: true

# Attendance status registry — the set of symbols a manager can put in an
# attendance cell (P/O/A/X + future ones). Kept as data (one row per symbol) so
# adding a new status is a row insert, not a code change. paid_fraction and
# penalty_days are decimals so half-days / partial penalties drop in later.
class CreateAttendanceStatuses < ActiveRecord::Migration[7.1]
  def change
    create_table :attendance_statuses, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true, index: true
      t.string :code, null: false
      t.string :symbol, null: false
      t.string :label, null: false
      t.decimal :paid_fraction, precision: 4, scale: 2, null: false, default: "1.0"
      t.decimal :penalty_days, precision: 4, scale: 2, null: false, default: "0.0"
      t.string :color
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :attendance_statuses, %i[company_id code], unique: true
    add_index :attendance_statuses, %i[company_id symbol], unique: true
  end
end
