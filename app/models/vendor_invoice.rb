# frozen_string_literal: true

class VendorInvoice < ApplicationRecord
  include Tenantable

  PAYMENT_STATUSES = %w[unpaid partially_paid paid void].freeze

  belongs_to :supplier
  belongs_to :user
  belongs_to :location
  has_many :vendor_invoice_lines, dependent: :destroy
  has_many :vendor_invoice_payments, dependent: :destroy

  accepts_nested_attributes_for :vendor_invoice_lines,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  monetize :total_cents
  monetize :amount_paid_cents

  validates :invoice_number, presence: true,
    uniqueness: { scope: %i[company_id supplier_id], case_sensitive: false }
  validates :invoice_date, :received_on, presence: true
  validates :location, presence: true
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :amount_paid_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :amount_paid_not_above_total

  scope :unpaid, -> { where(payment_status: "unpaid") }
  scope :partially_paid, -> { where(payment_status: "partially_paid") }
  scope :paid, -> { where(payment_status: "paid") }
  scope :outstanding, -> { where(payment_status: %w[unpaid partially_paid]) }
  scope :recent, -> { order(invoice_date: :desc, created_at: :desc) }

  before_save :recalculate_total

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

  def editable?
    unpaid? && amount_paid_cents.zero? && !void?
  end

  def stock_intact_for_edit?
    vendor_invoice_lines.all? do |line|
      batch = line.stock_batch
      batch.nil? || batch.quantity_remaining.to_d >= line.quantity.to_d
    end
  end

  def fully_editable?
    editable? && stock_intact_for_edit?
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

  def recalculate_total
    lines = vendor_invoice_lines.reject(&:marked_for_destruction?)
    self.total_cents = lines.sum { |line| (line.quantity.to_d * line.unit_price_cents).round }
  end

  def amount_paid_not_above_total
    return if amount_paid_cents.to_i <= total_cents.to_i

    errors.add(:amount_paid_cents, "cannot exceed invoice total")
  end
end
