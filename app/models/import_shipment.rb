# frozen_string_literal: true

# An import shipment: the container that assembles a product's true landed cost
# over time — goods (vendor invoices) plus customs/freight/clearance cost lines.
class ImportShipment < ApplicationRecord
  include Tenantable

  STATUSES = %w[open finalized].freeze

  belongs_to :user
  belongs_to :location, optional: true
  has_many :vendor_invoices, dependent: :nullify
  has_many :shipment_costs, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :shipment_number, presence: true,
    uniqueness: { scope: :company_id, case_sensitive: false }

  before_validation :assign_number, on: :create

  scope :open_shipments, -> { where(status: "open") }
  scope :recent, -> { order(arrival_date: :desc, created_at: :desc) }

  def self.next_number(company: Current.company, year: Date.current.year)
    prefix = "SHP-#{year}-"
    return "#{prefix}00001" if company.blank?

    max_seq = unscoped_by_company
      .where(company_id: company.id)
      .where("shipment_number ~ ?", "^SHP-#{year}-[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(shipment_number FROM #{prefix.length + 1}) AS INTEGER)"))

    format("%s%05d", prefix, (max_seq || 0) + 1)
  end

  def open?      = status == "open"
  def finalized? = status == "finalized"

  def total_costs_cents
    shipment_costs.sum(:amount_cents)
  end

  # The stock batches produced by this shipment's vendor invoices — the products
  # the landed cost is allocated across.
  def stock_batches
    StockBatch.joins(vendor_invoice_line: :vendor_invoice)
      .where(vendor_invoices: { import_shipment_id: id })
  end

  private

  def assign_number
    return if shipment_number.present?

    self.shipment_number = self.class.next_number(company: company || Current.company)
  end
end
