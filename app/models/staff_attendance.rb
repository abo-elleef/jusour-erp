# frozen_string_literal: true

# One staff member's status on one day. No row = never touched (an unpaid,
# not-counted day) — that blank encodes "not employed / off-roster". A row
# with a nil attendance_status = explicitly cleared after being set, kept
# (not destroyed) so its audit trail — who touched this day and when — stays
# attached to one stable record instead of churning row ids every time the
# day is set, cleared, and set again. See AuditLogEntry for that trail.
class StaffAttendance < ApplicationRecord
  include Tenantable

  belongs_to :user
  belongs_to :attendance_status, optional: true
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :date, presence: true
  validates :user_id, uniqueness: { scope: :date }

  scope :for_month, lambda { |month|
    month = month.to_date
    where(date: month.beginning_of_month..month.end_of_month)
  }
  scope :recorded, -> { where.not(attendance_status_id: nil) }
end
