# frozen_string_literal: true

# سند قبض / سند صرف — the document for money crossing a treasury.
#
# Its date is the date the cash moved, which is deliberately not the date the
# income or expense it settles was booked. What it settles is recorded in
# payment_allocations, so one voucher can clear several things at once.
class Voucher < ApplicationRecord
  include Tenantable
  include MoneyInputs
  include Partyable

  audited associated_with: :company

  money_input :amount_cents

  RECEIPT   = "receipt"
  PAYMENT   = "payment"
  DIRECTIONS = [RECEIPT, PAYMENT].freeze

  # Separate books, as سند قبض and سند صرف are kept separately on paper.
  PREFIXES = { RECEIPT => "RV", PAYMENT => "PV" }.freeze

  # A settlement clears what it settles. An adjustment has nothing to settle by
  # definition — cash appearing in or leaving a treasury with no counterparty
  # document — so its far side is equity, which is where "adjust balance"
  # always posted it.
  SETTLEMENT        = "settlement"
  EQUITY_ADJUSTMENT = "equity_adjustment"
  PURPOSES = [SETTLEMENT, EQUITY_ADJUSTMENT].freeze

  belongs_to :treasury
  belongs_to :user
  belongs_to :voided_by, class_name: "User", optional: true
  # The voucher issued in this one's place, when it was voided because the
  # record it settled changed.
  belongs_to :replaced_by, class_name: "Voucher", optional: true
  has_one :replaces, class_name: "Voucher", foreign_key: :replaced_by_id, dependent: :nullify

  has_many :payment_allocations, as: :payment, dependent: :destroy

  has_one_attached :receipt_image

  monetize :amount_cents

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :purpose, inclusion: { in: PURPOSES }
  validates :voucher_date, presence: true
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :number, presence: true,
                     uniqueness: { scope: :company_id, case_sensitive: false }

  before_validation :assign_number, on: :create

  # A backfilled voucher documents cash that moved before vouchers existed. It
  # carries a number, a date and its allocation, and posts nothing — the expense
  # or income it describes already wrote the treasury row and the journal entry.
  # Anything summing voucher cash must start from `posting`.
  # Voided vouchers stay in the book — they are why a number is missing from the
  # sequence — but they have settled nothing and moved no money since.
  scope :active, -> { where(voided_at: nil) }
  scope :voided, -> { where.not(voided_at: nil) }

  scope :posting,    -> { where(backfilled_at: nil) }
  scope :backfilled, -> { where.not(backfilled_at: nil) }

  scope :receipts, -> { where(direction: RECEIPT) }
  scope :payments, -> { where(direction: PAYMENT) }
  scope :recent,   -> { order(voucher_date: :desc, created_at: :desc) }
  scope :on_date_range, ->(start_date, end_date) { where(voucher_date: start_date..end_date) }

  # Staff vouchers for a payroll month: those dated in the month, except that
  # a salary payout paid after its own month (October's pay on 3 November)
  # counts in the month it pays for, not the one it's dated in.
  def self.for_staff_month(month)
    month = month.to_date.beginning_of_month
    late = PayrollSnapshot.paid_late
    staff = active.where(party_type: "User")
    staff.where(voucher_date: month..month.end_of_month).where.not(id: late.select(:payout_voucher_id))
         .or(staff.where(id: late.for_month(month).select(:payout_voucher_id)))
  end

  # Prepended so it runs before `dependent: :destroy` clears the allocations —
  # they are the only route back to what this voucher paid off.
  before_destroy :unapply_from_invoices, prepend: true
  after_destroy :remove_ledger

  # Voiding is how a voucher is undone. The money goes back, the entry is
  # removed, what it settled is released — and the document stays in the book,
  # marked, so the number it used is never handed out again and the hole it
  # leaves in the sequence has something in it.
  #
  # Destroying one is still possible and still cleans up after itself, but
  # nothing in the app does it any more: a document that was issued and printed
  # should not be able to vanish.
  def void!(user: nil, reason: nil, replaced_by: nil)
    return self if voided?

    transaction do
      unapply_from_invoices
      remove_ledger
      payment_allocations.destroy_all
      update!(voided_at: Time.current, voided_by: user,
              voided_reason: reason, replaced_by: replaced_by)
    end

    self
  end
  def backfilled?          = backfilled_at.present?
  def voided?              = voided_at.present?
  def equity_adjustment?   = purpose == EQUITY_ADJUSTMENT

  # An adjustment keeps the `adjustment` treasury kind it has always had. The
  # kind says what sort of movement this was, and the cash flow statement and
  # the profit-to-cash bridge both read it; the voucher is the paperwork that
  # was missing, not a reclassification of the money.
  #
  # Money to or from an employee gets its own pair of kinds so the cash flow
  # statement can still show what went to staff as one line — it used to be
  # `payroll_advance` / `payroll_salary` before the employee became an account.
  def treasury_kind
    return "adjustment" if equity_adjustment?
    return(receipt? ? "staff_receipt" : "staff_payment") if staff?

    receipt? ? "voucher_receipt" : "voucher_payment"
  end

  def staff? = party_type == "User"

  # True when the voucher settles at least one thing and everything it settles
  # is of the given type — the kind describes the whole movement, so a mixed
  # voucher stays a plain voucher.
  def settles_only?(klass)
    targets = payment_allocations.map(&:settles)
    targets.any? && targets.all? { |t| t.is_a?(klass) }
  end
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

  # Free-text search for the vouchers list: the number, the notes, the typed
  # counterparty, and the party's name — the voucher's own party, or the one
  # behind an invoice it settled (that is what the list shows for most
  # settlement vouchers, so searching by it has to work). Also matches the
  # number of an invoice it settled.
  def self.search_text(term)
    term = term.to_s.strip
    return all if term.blank?

    like = "%#{sanitize_sql_like(term)}%"
    named = ->(klass, column = :name) { klass.where("#{klass.table_name}.#{column} ILIKE ?", like).select(:id) }

    own_party = Partyable::PARTY_TYPES.map do |type|
      klass = type.constantize
      where(party_type: type, party_id: named.call(klass))
    end

    settled = PaymentAllocation.where(payment_type: "Voucher").select(:payment_id)
    via_vendor_invoice = where(id: settled.where(settles_type: "VendorInvoice", settles_id:
      VendorInvoice.where(supplier_id: named.call(Supplier)).or(VendorInvoice.where("invoice_number ILIKE ?", like)).select(:id)))
    via_customer_invoice = where(id: settled.where(settles_type: "CustomerInvoice", settles_id:
      CustomerInvoice.where(customer_id: named.call(Customer)).or(CustomerInvoice.where("invoice_number ILIKE ?", like)).select(:id)))

    text = where("vouchers.number ILIKE :q OR vouchers.notes ILIKE :q OR vouchers.counterparty ILIKE :q", q: like)
    [*own_party, via_vendor_invoice, via_customer_invoice].inject(text) { |scope, other| scope.or(other) }
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
