# frozen_string_literal: true

class VendorInvoicePayment < ApplicationRecord
  include Tenantable

  belongs_to :vendor_invoice
  belongs_to :user
  belongs_to :treasury
  has_one :expense, as: :source_record, dependent: :nullify

  monetize :amount_cents

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :payment_date, presence: true
end
