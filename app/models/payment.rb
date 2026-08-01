# frozen_string_literal: true

class Payment < ApplicationRecord
  METHODS = %w[cash card apple_pay google_pay gift_card instapay vodafone_cash staff_deduction].freeze

  scope :staff_deduction, -> { where(payment_method: "staff_deduction") }
  DIGITAL_WALLET_METHODS = %w[instapay vodafone_cash].freeze
  STATUSES = %w[pending completed failed refunded partially_refunded].freeze

  belongs_to :company
  belongs_to :order
  belongs_to :processed_by_user, class_name: "User", optional: true
  belongs_to :cash_drawer_session, optional: true

  monetize :amount_cents
  monetize :tip_cents, allow_nil: false
  monetize :refunded_amount_cents, allow_nil: false

  validates :payment_method, inclusion: { in: METHODS }
  validates :status, inclusion: { in: STATUSES }
  validates :company, presence: true

  before_validation :assign_company_from_order, on: :create

  after_create do
    AuditLogEntry.record!(
      action: "payment.create",
      record: self,
      user: processed_by_user
    )
  end

  private

  def assign_company_from_order
    self.company ||= order&.company
  end
end
