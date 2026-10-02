# frozen_string_literal: true

# Attendance change-logging (rake attendance:backfill_audit_history's reason
# for existing) only started recording AuditLogEntry rows from the day it
# shipped — every StaffAttendance row created before that has no history at
# all. This gives each of those one synthetic "create" entry, so a row that
# predates the feature at least shows who created it and when, same as a
# real first entry would — using recorded_by/updated_at as the best
# available stand-in, not a reconstruction of real intermediate edits (those
# were never captured and can't be recovered).
#
#   bin/rails attendance:backfill_audit_history
#
# Safe to re-run: only rows with zero existing audit entries are touched.
namespace :attendance do
  desc "Give every existing attendance record with no audit history a synthetic first entry"
  task backfill_audit_history: :environment do
    # Both .unscoped — this must span every company regardless of whatever
    # Current.company happens to be set to when the task runs (nil from a
    # plain rake invocation, but console/test usage can leave it set).
    scope = StaffAttendance.unscoped
      .where.not(id: AuditLogEntry.unscoped.where(record_type: "StaffAttendance").select(:record_id))

    total = scope.count
    if total.zero?
      puts "Every attendance record already has at least one audit entry."
      next
    end

    created = 0
    failed = 0

    scope.find_each do |record|
      AuditLogEntry.record!(
        action: "create",
        record: record,
        user: record.recorded_by,
        changes_snapshot: { "attendance_status_id" => [nil, record.attendance_status_id] },
        created_at: record.updated_at
      )
      created += 1
    rescue StandardError => e
      failed += 1
      warn "Failed for StaffAttendance #{record.id}: #{e.message}"
    end

    puts "Backfilled #{created}/#{total} attendance record(s). Failed: #{failed}."
  end
end
