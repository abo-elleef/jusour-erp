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

  # A backfilled voucher documents cash that moved before vouchers existed. It
  # carries a number, a date and its allocation, and posts nothing — the expense
  # or income it describes already wrote the treasury row and the journal entry.
  # Anything summing voucher cash must start from `posting`.
  scope :posting,    -> { where(backfilled_at: nil) }
  scope :backfilled, -> { where.not(backfilled_at: nil) }

  scope :receipts, -> { where(direction: RECEIPT) }
  scope :payments, -> { where(direction: PAYMENT) }
  scope :recent,   -> { order(voucher_date: :desc, created_at: :desc) }
  scope :on_date_range, ->(start_date, end_date) { where(voucher_date: start_date..end_date) }

  # Prepended so it runs before `dependent: :destroy` clears the allocations —
  # they are the only route back to what this voucher paid off.
  before_destroy :unapply_from_invoices, prepend: true
  after_destroy :remove_ledger

  def backfilled? = backfilled_at.present?
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

  # Destroying a voucher takes its cash back out of the treasury and removes the
  # entry, the same way an expense has always undone itself. A backfilled voucher
  # posted nothing, so there is nothing to undo.
  # The mirror of Accounting::RecordVoucherService#apply_to_invoices!. An
  # invoice carries its own paid-to-date, so voiding the voucher that paid it
  # has to give that back; an expense or income derives its outstanding amount
  # from the allocations, which go on their own.
  def unapply_from_invoices
    return if backfilled?

    payment_allocations.each do |allocation|
      invoice = allocation.settles
      next unless invoice.is_a?(VendorInvoice) || invoice.is_a?(CustomerInvoice)

      invoice.update!(amount_paid_cents: [invoice.amount_paid_cents - allocation.amount_cents, 0].max)
      invoice.sync_payment_status!
    end
  end

  def remove_ledger
    return if backfilled?

    Accounting::TreasuryLedgerService.remove_source!(self)
    Accounting::JournalEntryService.destroy_for_source!(self)
  end

  def assign_number
    return if number.present? || direction.blank?

    self.number = self.class.next_number(direction: direction,
                                         company: company || Current.company)
  end
end
