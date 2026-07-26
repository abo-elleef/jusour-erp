# frozen_string_literal: true

# A status can now grant bonus days (e.g. PP = a paid day + 1 bonus day),
# alongside paid_fraction and penalty_days.
class AddBonusDaysToAttendanceStatuses < ActiveRecord::Migration[7.1]
  def change
    add_column :attendance_statuses, :bonus_days, :decimal, precision: 4, scale: 2, null: false, default: "0.0"
  end
end
