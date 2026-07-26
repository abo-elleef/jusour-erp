# frozen_string_literal: true

# One row per staff member per day. Absence of a row for a given (user, date)
# means "unrecorded / not a paid day" — that blank is how mid-month joiners and
# leavers are handled without tracking hire/fire dates.
class CreateStaffAttendances < ActiveRecord::Migration[7.1]
  def change
    create_table :staff_attendances, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true, index: true
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true
      t.references :attendance_status, type: :uuid, null: false, foreign_key: true, index: true
      t.references :recorded_by, type: :uuid, foreign_key: { to_table: :users }
      t.date :date, null: false
      t.text :notes
      t.timestamps
    end

    add_index :staff_attendances, %i[user_id date], unique: true
    add_index :staff_attendances, %i[company_id date]
  end
end
