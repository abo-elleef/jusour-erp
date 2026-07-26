# frozen_string_literal: true

# Policy change: an excused absence (A — staff informed the manager) is now
# unpaid (still no penalty, unlike X). Update already-seeded rows to match.
class MakeExcusedAbsenceUnpaid < ActiveRecord::Migration[7.1]
  def up
    execute "UPDATE attendance_statuses SET paid_fraction = 0 WHERE code = 'excused'"
  end

  def down
    execute "UPDATE attendance_statuses SET paid_fraction = 1 WHERE code = 'excused'"
  end
end
