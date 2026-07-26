# frozen_string_literal: true

class ShiftLog < ApplicationRecord
  include Tenantable

  STATUSES = %w[active completed adjusted].freeze

  belongs_to :user
  has_many :expenses, as: :source_record, dependent: :nullify

  monetize :hourly_rate_cents
  monetize :tips_cents

  validates :clocked_in_at, :hourly_rate_cents, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :break_minutes, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(status: "active") }
  scope :completed, -> { where(status: %w[completed adjusted]) }

  after_update :audit_status_change, if: -> { saved_change_to_status? && status == "adjusted" }

  def hours_worked
    return 0 unless clocked_out_at

    elapsed = (clocked_out_at - clocked_in_at) / 3600.0
    [elapsed - (break_minutes / 60.0), 0].max
  end

  # When the shift's order window ends: clock-out time, or "now" while active.
  def orders_ended_at
    clocked_out_at || Time.current
  end

  # Orders placed by this cashier during the shift. There is no FK from orders
  # to shifts, so association is by user + creation time window (mirrors
  # User#shift_orders_time_range used by the POS shift screen).
  def orders
    Order.where(user_id: user_id, created_at: clocked_in_at..orders_ended_at)
  end

  # Estimated wage cost for the hours worked (excludes tips).
  def labor_cost_cents
    (hours_worked * hourly_rate_cents).round
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[status clocked_in_at clocked_out_at user_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[user]
  end

  private

  def audit_status_change
    AuditLogEntry.record!(
      action: "shift.adjust",
      record: self,
      user: user,
      changes_snapshot: { status: [status_before_last_save, status] }
    )
  end
end
