# frozen_string_literal: true

# One payment method a branch offers to self-ordering customers. With
# requires_proof the customer pays first (InstaPay, Vodafone Cash) and attaches a
# screenshot; the cashier checks it and accepting the order records the payment.
# Without it the customer pays on delivery or pickup, by that method.
#
# Only the methods the POS already knows are offered — see Payment::METHODS.
class OnlinePaymentMethod < ApplicationRecord
  include Tenantable

  METHODS = %w[cash instapay vodafone_cash].freeze

  belongs_to :location

  validates :payment_method, inclusion: { in: METHODS }, uniqueness: { scope: :location_id }
  validate :cash_cannot_require_proof

  before_validation { self.pay_to = pay_to.to_s.strip.first(300).presence }

  def cash? = payment_method == "cash"

  private

  def assign_company
    self.company ||= location&.company || Current.company
  end

  def cash_cannot_require_proof
    errors.add(:requires_proof, :invalid) if cash? && requires_proof?
  end
end
