# frozen_string_literal: true

# A payment received from a customer against their AR balance. Recording one
# (see Sales::RecordCustomerPaymentService) settles the AR ledger and allocates
# the amount FIFO across the customer's outstanding invoices.
class CustomerPayment < ApplicationRecord
  include Tenantable

  belongs_to :customer
  belongs_to :user
  belongs_to :treasury

  monetize :amount_cents

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :payment_date, presence: true

  has_many :payment_allocations, as: :payment, dependent: :destroy

  scope :recent, -> { order(payment_date: :desc, created_at: :desc) }

  # What is left after the invoices this payment was applied to — the part the
  # customer is in credit for. Derived, never stored.
  def unallocated_cents
    amount_cents - payment_allocations.sum(:amount_cents)
  end
end
