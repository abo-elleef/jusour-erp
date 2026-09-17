# frozen_string_literal: true

class VendorInvoicePayment < ApplicationRecord
  include Tenantable

  belongs_to :vendor_invoice
  belongs_to :user
  belongs_to :treasury
  has_one :expense, as: :source_record, dependent: :nullify
  has_many :payment_allocations, as: :payment, dependent: :destroy

  monetize :amount_cents

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :payment_date, presence: true
end
