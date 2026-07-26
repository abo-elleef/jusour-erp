# frozen_string_literal: true

# Backfill the default P/O/A/X statuses for companies that already exist.
# New companies get them via Company after_create :seed_default_attendance_statuses.
class SeedAttendanceStatusesForExistingCompanies < ActiveRecord::Migration[7.1]
  def up
    Company.reset_column_information
    Company.find_each { |company| AttendanceStatus.seed_defaults!(company) }
  end

  def down
    # Irreversible seed; leave rows in place.
  end
end
