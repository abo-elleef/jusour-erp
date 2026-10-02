class MakeStaffAttendanceStatusOptional < ActiveRecord::Migration[7.1]
  def change
    # Clearing a day now nils the status on the same row (instead of deleting
    # it), so the row's audit trail stays attached to one stable record.
    change_column_null :staff_attendances, :attendance_status_id, true
  end
end
