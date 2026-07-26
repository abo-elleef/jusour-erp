# frozen_string_literal: true

# One staff member's status on one day. No row = unrecorded (an unpaid,
# not-counted day) — that blank encodes "not employed / off-roster".
class StaffAttendance < ApplicationRecord
  include Tenantable

  belongs_to :user
  belongs_to :attendance_status
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :date, presence: true
  validates :user_id, uniqueness: { scope: :date }

  scope :for_month, lambda { |month|
    month = month.to_date
    where(date: month.beginning_of_month..month.end_of_month)
  }
end
