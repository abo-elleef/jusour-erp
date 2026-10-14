# frozen_string_literal: true

# A B2B sales invoice — the customer-side mirror of VendorInvoice. Built as a
# draft, then confirmed (see Sales::ConfirmCustomerInvoiceService), which raises
# AR and deducts stock. Prices are firm at sale.
class CustomerInvoice < ApplicationRecord
  include Tenantable
  include MoneyInputs
  money_input :delivery_fee_cents, :standard_delivery_fee_cents

  # historical = a sale that really happened before this system, imported from the
  # previous one. It counts as a sale in the operational sales reports, but it
  # never touches the ledger, AR or stock — the money and the goods moved long
  # before we existed, so replaying them would double-count. It is terminal: a
  # historical invoice can't be confirmed (see Sales::ConfirmCustomerInvoiceService).
  # pending_payment_confirmation = a draft submitted with an online payment
  # method, sitting in the approval queue (see Sales::ConfirmCustomerInvoiceService)
  # until someone with sales:confirm_payments approves or rejects it. Stock
  # has not moved yet — that still only happens on confirm.
  STATUSES = %w[draft pending_payment_confirmation confirmed historical void].freeze
  PAYMENT_STATUSES = %w[unpaid partially_paid paid].freeze
  FULFILLMENT_METHODS = %w[pickup delivery].freeze

  # How the sale is settled.
  #   on_account        — the credit sale this module was built for; raises a receivable.
  #   cash               — paid at the counter on the spot; banks straight into a treasury.
  #   cash_on_delivery   — a delivery where the shipping company collects cash from the
  #                        customer and owes it to us until they remit it. Nothing is
  #                        banked at confirm — see Sales::DispatchCustomerInvoiceService.
  #   online             — a configurable online method (Sales::PaymentMethod); needs
  #                        approval before it settles (see pending_payment_confirmation).
  ON_ACCOUNT = "on_account"
  CASH = "cash"
  CASH_ON_DELIVERY = "cash_on_delivery"
  ONLINE = "online"
  PAID_NOW_METHODS = [CASH, CASH_ON_DELIVERY, ONLINE].freeze
  PAYMENT_METHODS = [ON_ACCOUNT, *PAID_NOW_METHODS].freeze

  belongs_to :customer
  belongs_to :user
  belongs_to :location
  # Set when the sale is paid at the counter rather than put on account: the
  # treasury the money went into. Its presence is what makes this a cash sale.
  belongs_to :treasury, optional: true
  # The teammate credited with the sale (drives their sales bonus), separate from
  # `user` who recorded it. Defaults to the recorder.
  belongs_to :salesperson, class_name: "User", optional: true
  # Required when fulfillment_method is "delivery" — see validate :shipping_company_required_for_delivery.
  belongs_to :shipping_company, optional: true
  # Required when payment_method is "online" — which configured method/treasury was used.
  belongs_to :sales_payment_method, class_name: "Sales::PaymentMethod", optional: true

  # Evidence of payment — an InstaPay/bank-transfer screenshot, mainly. Mirrors
  # VendorInvoice#invoice_image: one attachment, replace to change, no delete.
  has_one_attached :payment_proof_image

  before_validation :default_salesperson
  has_many :customer_invoice_lines, -> { order(:position, :created_at) },
    dependent: :destroy, inverse_of: :customer_invoice

  has_many :payment_allocations, as: :settles, dependent: :destroy
  has_many :payment_vouchers, -> { distinct.active.order(voucher_date: :desc, created_at: :desc) },
           through: :payment_allocations, source: :payment, source_type: "Voucher"

  accepts_nested_attributes_for :customer_invoice_lines, allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  monetize :total_cents
  monetize :amount_paid_cents
  monetize :delivery_fee_cents
  monetize :standard_delivery_fee_cents

  validates :invoice_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :fulfillment_method, inclusion: { in: FULFILLMENT_METHODS }
  validates :invoice_number, presence: true,
    uniqueness: { scope: :company_id, case_sensitive: false }
  validates :delivery_fee_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :standard_delivery_fee_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :shipping_company_required_for_delivery
  validate :sales_payment_method_required_for_online
  validate :delivery_fee_within_standard

  before_validation :assign_invoice_number, on: :create
  before_validation :default_blank_delivery_fees
  before_validation :zero_delivery_fees_for_pickup
  before_save :recalculate_total

  scope :draft, -> { where(status: "draft") }
  scope :pending_payment_confirmation, -> { where(status: "pending_payment_confirmation") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :historical, -> { where(status: "historical") }
  scope :on_account, -> { where(payment_method: ON_ACCOUNT) }
  scope :paid_on_issue, -> { where.not(payment_method: ON_ACCOUNT) }
  # Every invoice that represents a real sale, whether we booked it or inherited it.
  # This is what sales reporting counts; `confirmed` alone is what the ledger knows.
  scope :realized, -> { where(status: %w[confirmed historical]) }
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
  def pending_payment_confirmation? = status == "pending_payment_confirmation"
  def confirmed?  = status == "confirmed"
  def historical? = status == "historical"
  def void?       = status == "void"

  # Nothing has posted yet in either state — no stock deducted, no treasury or
  # AR entry — so voiding is just marking it dead, the same reasoning
  # Sales::CreditNotesController#void uses for a draft credit note. A confirmed
  # invoice already moved stock/money and isn't handled here.
  def voidable?   = draft? || pending_payment_confirmation?

  # Paid on issue — the customer settled (or will settle) outside of AR, so
  # this sale never becomes a receivable on the customer's own statement.
  def paid_on_issue? = payment_method != ON_ACCOUNT
  def on_account?    = payment_method == ON_ACCOUNT
  def cash?             = payment_method == CASH
  def cash_on_delivery? = payment_method == CASH_ON_DELIVERY
  def online?           = payment_method == ONLINE

  def delivery? = fulfillment_method == "delivery"
  def pickup?   = fulfillment_method == "pickup"
  def dispatched? = dispatched_at.present?

  def subtotal_cents
    customer_invoice_lines.reject(&:marked_for_destruction?).sum(&:line_total_cents)
  end

  # Delivery fee actually waived by a promo on this invoice — what the
  # courier is still owed (see Accounting::ShippingCompanyLedgerService#accrue_delivery_fee!)
  # but Bazzar chose not to bill the customer for.
  def waived_delivery_fee_cents
    standard_delivery_fee_cents - delivery_fee_cents
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
    self.total_cents = subtotal_cents + delivery_fee_cents
  end

  def assign_invoice_number
    return if invoice_number.present?

    self.invoice_number = self.class.next_invoice_number(company: company || Current.company)
  end

  def shipping_company_required_for_delivery
    return unless delivery?

    errors.add(:shipping_company, :blank) if shipping_company.blank?
  end

  def sales_payment_method_required_for_online
    return unless online?

    errors.add(:sales_payment_method, :blank) if sales_payment_method.blank?
  end

  def delivery_fee_within_standard
    return if delivery_fee_cents.to_i <= standard_delivery_fee_cents.to_i

    errors.add(:delivery_fee_cents, :greater_than_standard, message: "can't exceed the standard delivery fee")
  end

  # A blank delivery-fee input (the form's money_input setter turns "" into
  # nil) means "leave it at 0", not "no value" — nil would fail the
  # numericality validation and the DB's NOT NULL constraint.
  def default_blank_delivery_fees
    self.delivery_fee_cents ||= 0
    self.standard_delivery_fee_cents ||= 0
  end

  # Pickup orders never carry a delivery fee — a fulfillment-method switch
  # (pickup → delivery → pickup) must not leave a stale fee behind.
  def zero_delivery_fees_for_pickup
    return unless pickup?

    self.delivery_fee_cents = 0
    self.standard_delivery_fee_cents = 0
  end
end
