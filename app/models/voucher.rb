# frozen_string_literal: true

# سند قبض / سند صرف — the document for money crossing a treasury.
#
# Its date is the date the cash moved, which is deliberately not the date the
# income or expense it settles was booked. What it settles is recorded in
# payment_allocations, so one voucher can clear several things at once.
class Voucher < ApplicationRecord
  include Tenantable
  include MoneyInputs

  audited associated_with: :company

  money_input :amount_cents

  RECEIPT   = "receipt"
  PAYMENT   = "payment"
  DIRECTIONS = [RECEIPT, PAYMENT].freeze

  # Separate books, as سند قبض and سند صرف are kept separately on paper.
  PREFIXES = { RECEIPT => "RV", PAYMENT => "PV" }.freeze

  belongs_to :treasury
  belongs_to :user

  has_many :payment_allocations, as: :payment, dependent: :destroy

  has_one_attached :receipt_image

  monetize :amount_cents

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :voucher_date, presence: true
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :number, presence: true,
                     uniqueness: { scope: :company_id, case_sensitive: false }

  before_validation :assign_number, on: :create

  scope :receipts, -> { where(direction: RECEIPT) }
  scope :payments, -> { where(direction: PAYMENT) }
  scope :recent,   -> { order(voucher_date: :desc, created_at: :desc) }
  scope :on_date_range, ->(start_date, end_date) { where(voucher_date: start_date..end_date) }

  def receipt? = direction == RECEIPT
  def payment? = direction == PAYMENT

  # Signed against the treasury: a receipt brings money in, a payment takes it out.
  def signed_amount_cents
    receipt? ? amount_cents : -amount_cents
  end

  # What this voucher has not been applied to anything — money received on
  # account, or paid ahead of the bill it will eventually clear.
  def unallocated_cents
    amount_cents - payment_allocations.sum(:amount_cents)
  end

  # "RV-<year>-<sequence>" / "PV-<year>-<sequence>", per company, resetting each
  # year — the scheme SI-, VI- and JE- already use.
  def self.next_number(direction:, company: Current.company, year: Date.current.year)
    prefix = "#{PREFIXES.fetch(direction)}-#{year}-"
    return "#{prefix}00001" if company.blank?

    max_seq = unscoped_by_company
      .where(company_id: company.id, direction: direction)
      .where("number ~ ?", "^#{prefix}[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(number FROM #{prefix.length + 1}) AS INTEGER)"))

    format("%s%05d", prefix, (max_seq || 0) + 1)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[number direction voucher_date amount_cents treasury_id counterparty]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[treasury user]
  end

  private

  def assign_number
    return if number.present? || direction.blank?

    self.number = self.class.next_number(direction: direction,
                                         company: company || Current.company)
  end
end
