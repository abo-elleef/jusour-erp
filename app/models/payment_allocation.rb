# frozen_string_literal: true

# One payment applied to one thing it settles, for one amount.
#
# The record that was missing: until now a customer payment was spread across
# outstanding invoices FIFO and the split was thrown away, so an invoice could
# say it was paid without being able to say by what. Vouchers will settle far
# more than invoices, and they will do it through this table.
class PaymentAllocation < ApplicationRecord
  include Tenantable

  belongs_to :payment, polymorphic: true
  belongs_to :settles, polymorphic: true

  monetize :amount_cents

  validates :amount_cents, numericality: { greater_than: 0 }

  scope :for_payment, ->(payment) { where(payment: payment) }
  scope :for_settled, ->(record)  { where(settles: record) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[amount_cents payment_type settles_type created_at]
  end
end
