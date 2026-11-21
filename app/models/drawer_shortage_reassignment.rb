# frozen_string_literal: true

# One move of a drawer shortage from one staff member to another, made by the
# accountant while reviewing the day (Accounting::ReassignDrawerShortage). The
# drawer itself only knows who carries the shortage now; these rows are the
# history behind it and feed the "shortage moves" report.
class DrawerShortageReassignment < ApplicationRecord
  include Tenantable

  belongs_to :cash_drawer_session
  belongs_to :from_user, class_name: "User"
  belongs_to :to_user, class_name: "User"
  belongs_to :reassigned_by, class_name: "User"
  # The voucher voided by the move and the one issued in its place.
  belongs_to :old_voucher, class_name: "Voucher", optional: true
  belongs_to :new_voucher, class_name: "Voucher", optional: true

  monetize :amount_cents

  validates :reason, presence: true
  validates :amount_cents, numericality: { greater_than: 0 }
  validate :moves_to_someone_else

  scope :recent_first, -> { order(created_at: :desc) }

  private

  def moves_to_someone_else
    errors.add(:to_user, :invalid) if from_user_id.present? && from_user_id == to_user_id
  end
end
