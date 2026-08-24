# frozen_string_literal: true

class VendorInvoice < ApplicationRecord
  include Tenantable

  PAYMENT_STATUSES = %w[unpaid partially_paid paid void].freeze
  DISCOUNT_TYPES = %w[percentage fixed_amount].freeze

  belongs_to :supplier
  belongs_to :user
  belongs_to :location
  has_many :vendor_invoice_lines, -> { order(:position, :created_at) }, dependent: :destroy, inverse_of: :vendor_invoice
  has_many :vendor_invoice_payments, dependent: :destroy
  # Courier freight paid at receive — separate from supplier AP / Vendor purchases payments.
  has_one :freight_expense, as: :source_record, class_name: "Expense", dependent: :nullify

  has_one_attached :invoice_image

  accepts_nested_attributes_for :vendor_invoice_lines,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  monetize :total_cents
  monetize :amount_paid_cents

  validates :invoice_number, presence: true,
    uniqueness: { scope: %i[company_id supplier_id], case_sensitive: false }
  validates :invoice_date, :received_on, presence: true
  validates :location, presence: true, unless: :draft?
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :freight_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :amount_paid_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :discount_type, inclusion: { in: DISCOUNT_TYPES }, allow_nil: true
  validates :discount_value, numericality: { greater_than: 0 }, allow_nil: true
  validate :discount_type_and_value_consistency
  validate :discount_percentage_range
  validate :amount_paid_not_above_total

  # Drafts have posted nothing, so they must stay out of anything that reads real
  # activity — AP, costing, reports. `posted` is the default lens.
  scope :drafts, -> { where(draft: true) }
  scope :posted, -> { where(draft: false) }
  scope :unpaid, -> { where(payment_status: "unpaid") }
  scope :partially_paid, -> { where(payment_status: "partially_paid") }
  scope :paid, -> { where(payment_status: "paid") }
  scope :outstanding, -> { where(payment_status: %w[unpaid partially_paid]) }
  scope :recent, -> { order(invoice_date: :desc, created_at: :desc) }

  # Neighbors in the same order as the index list (newest invoice date first).
  def newer
    self.class
      .where(
        "(invoice_date > :date) OR (invoice_date = :date AND created_at > :created)",
        date: invoice_date, created: created_at
      )
      .order(invoice_date: :asc, created_at: :asc)
      .first
  end

  def older
    self.class
      .where(
        "(invoice_date < :date) OR (invoice_date = :date AND created_at < :created)",
        date: invoice_date, created: created_at
      )
      .order(invoice_date: :desc, created_at: :desc)
      .first
  end

  before_validation :assign_invoice_number, on: :create
  before_save :recalculate_total

  # "VI-<year>-<sequence>", e.g. VI-2026-00001. The sequence is company-wide and
  # resets each year. Legacy dated numbers (VI-YYYY-MM-DD-NNNN) are ignored when
  # computing the next value, so the yearly series starts clean.
  def self.next_invoice_number(company: Current.company, year: Date.current.year)
    prefix = "VI-#{year}-"
    return "#{prefix}00001" if company.blank?

    max_seq = unscoped_by_company
      .where(company_id: company.id)
      .where("invoice_number ~ ?", "^VI-#{year}-[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(invoice_number FROM #{prefix.length + 1}) AS INTEGER)"))

    format("%s%05d", prefix, (max_seq || 0) + 1)
  end

  def unpaid?
    payment_status == "unpaid"
  end

  def partially_paid?
    payment_status == "partially_paid"
  end

  def paid?
    payment_status == "paid"
  end

  def void?
    payment_status == "void"
  end

  def payable?
    !void? && balance_due_cents.positive?
  end

  # A draft posted nothing, so there is nothing to unwind — it is always editable,
  # and editing skips the reverse-and-re-receive a posted invoice needs.
  def editable?
    return true if draft?

    unpaid? && amount_paid_cents.zero? && !void?
  end

  def fully_editable?
    return true if draft?

    editable? && stock_intact_for_edit?
  end

  def postable?
    draft? && vendor_invoice_lines.any?
  end

  def stock_intact_for_edit?
    vendor_invoice_lines.all? do |line|
      batch = line.stock_batch
      batch.nil? || batch.quantity_remaining.to_d >= line.quantity.to_d
    end
  end

  def subtotal_cents
    vendor_invoice_lines.reject(&:marked_for_destruction?).sum(&:line_total_cents)
  end

  def discount_cents
    return 0 if discount_type.blank? || discount_value.blank?

    case discount_type
    when "percentage"
      (subtotal_cents * discount_value.to_d / 100).round
    when "fixed_amount"
      [discount_value.to_i, subtotal_cents].min
    else
      0
    end
  end

  # Goods after any discount — the discount applies to goods only, never delivery.
  def goods_total_cents
    [subtotal_cents - discount_cents, 0].max
  end

  # Delivery billed by the vendor on this invoice and settled with it. Only this
  # form of delivery belongs in total_cents, because total_cents is what drives
  # supplier AP and balance due. Delivery paid in cash at receive leaves through a
  # linked Expense instead and must stay out of the total.
  def freight_on_account_cents
    freight_on_account? ? freight_amount_cents.to_i : 0
  end

  def freight_paid_now?
    !freight_on_account? && freight_amount_cents.to_i.positive?
  end

  def discounted?
    discount_cents.positive?
  end

  def balance_due_cents
    total_cents - amount_paid_cents
  end

  def sync_payment_status!
    return if void?

    new_status = if amount_paid_cents.zero?
                   "unpaid"
                 elsif amount_paid_cents >= total_cents
                   "paid"
                 else
                   "partially_paid"
                 end

    update!(payment_status: new_status) if payment_status != new_status
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[invoice_number invoice_date received_on payment_status total_cents amount_paid_cents supplier_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[supplier user location]
  end

  private

  def assign_invoice_number
    return if invoice_number.present?

    self.invoice_number = self.class.next_invoice_number(company: company || Current.company)
  end

  def recalculate_total
    self.total_cents = goods_total_cents + freight_on_account_cents
  end

  def discount_type_and_value_consistency
    if discount_type.blank?
      errors.add(:discount_value, :present) if discount_value.present? && discount_value.to_d.positive?
      return
    end

    errors.add(:discount_value, :blank) if discount_value.blank? || discount_value.to_d <= 0
  end

  def discount_percentage_range
    return unless discount_type == "percentage"
    return if discount_value.blank?

    value = discount_value.to_d
    return if value.positive? && value <= 100

    errors.add(:discount_value, :inclusion, message: "must be between 0 and 100 for percentage discounts")
  end

  def amount_paid_not_above_total
    return if amount_paid_cents.to_i <= total_cents.to_i

    errors.add(:amount_paid_cents, "cannot exceed invoice total")
  end
end
