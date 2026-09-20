# frozen_string_literal: true

# One payment applied to one thing it settles, for one amount.
#
# The record that was missing: until now a customer payment was spread across
# outstanding invoices FIFO and the split was thrown away, so an invoice could
# say it was paid without being able to say by what. Vouchers will settle far
# more than invoices, and they will do it through this table.
class PaymentAllocation < ApplicationRecord
  include Tenantable

  # Everything a voucher can settle. Named here rather than left implicit so
  # that adding one is a decision with a checklist: the journal entry needs a
  # counter-account for it (JournalEntryService#counter_account_for), the
  # treasury side may need a counterparty leg, and every screen showing what a
  # voucher settled needs a label and a path (SettledRecordsHelper).
  #
  # The specs walk this list, so a type added here without those fails rather
  # than raising NoMethodError on a page nobody tested.
  SETTLEABLE_TYPES = %w[Expense Income VendorInvoice CustomerInvoice Customer Supplier
                        PayrollAdvance].freeze

  belongs_to :payment, polymorphic: true
  belongs_to :settles, polymorphic: true

  validates :settles_type, inclusion: { in: SETTLEABLE_TYPES }

  monetize :amount_cents

  validates :amount_cents, numericality: { greater_than: 0 }

  scope :for_payment, ->(payment) { where(payment: payment) }
  scope :for_settled, ->(record)  { where(settles: record) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[amount_cents payment_type settles_type created_at]
  end
end
