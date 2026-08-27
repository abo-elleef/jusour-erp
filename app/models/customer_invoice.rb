# frozen_string_literal: true

# A B2B sales invoice — the customer-side mirror of VendorInvoice. Built as a
# draft, then confirmed (see Sales::ConfirmCustomerInvoiceService), which raises
# AR and deducts stock. Prices are firm at sale.
class CustomerInvoice < ApplicationRecord
  include Tenantable

  STATUSES = %w[draft confirmed void].freeze
  PAYMENT_STATUSES = %w[unpaid partially_paid paid].freeze

  belongs_to :customer
  belongs_to :user
  belongs_to :location
  # The teammate credited with the sale (drives their sales bonus), separate from
  # `user` who recorded it. Defaults to the recorder.
  belongs_to :salesperson, class_name: "User", optional: true

  before_validation :default_salesperson
  has_many :customer_invoice_lines, -> { order(:position, :created_at) },
    dependent: :destroy, inverse_of: :customer_invoice

  accepts_nested_attributes_for :customer_invoice_lines, allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  monetize :total_cents
  monetize :amount_paid_cents

  validates :invoice_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :invoice_number, presence: true,
    uniqueness: { scope: :company_id, case_sensitive: false }

  before_validation :assign_invoice_number, on: :create
  before_save :recalculate_total

  scope :draft, -> { where(status: "draft") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :outstanding, -> { where(status: "confirmed", payment_status: %w[unpaid partially_paid]) }
  scope :recent, -> { order(invoice_date: :desc, created_at: :desc) }

  # "SI-<year>-<sequence>", company-wide, resetting each year — same scheme as
  # vendor invoices (VI-) and journal entries.
  def self.next_invoice_number(company: Current.company, year: Date.current.year)
    prefix = "SI-#{year}-"
    return "#{prefix}00001" if company.blank?

    max_seq = unscoped_by_company
      .where(company_id: company.id)
      .where("invoice_number ~ ?", "^SI-#{year}-[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(invoice_number FROM #{prefix.length + 1}) AS INTEGER)"))

    format("%s%05d", prefix, (max_seq || 0) + 1)
  end

  def draft?      = status == "draft"
  def confirmed?  = status == "confirmed"
  def void?       = status == "void"

  def subtotal_cents
    customer_invoice_lines.reject(&:marked_for_destruction?).sum(&:line_total_cents)
  end

  def balance_due_cents
    total_cents - amount_paid_cents
  end

  # Recompute payment_status from amount_paid vs total. Called after a payment is
  # allocated to this invoice.
  def sync_payment_status!
    new_status = if amount_paid_cents <= 0
                   "unpaid"
                 elsif amount_paid_cents >= total_cents
                   "paid"
                 else
                   "partially_paid"
                 end
    update!(payment_status: new_status) if payment_status != new_status
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[invoice_number invoice_date status payment_status total_cents customer_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[customer user location]
  end

  private

  def default_salesperson
    self.salesperson ||= user
  end

  def recalculate_total
    self.total_cents = subtotal_cents
  end

  def assign_invoice_number
    return if invoice_number.present?

    self.invoice_number = self.class.next_invoice_number(company: company || Current.company)
  end
end
