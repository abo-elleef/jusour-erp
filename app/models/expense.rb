# frozen_string_literal: true

class Expense < ApplicationRecord
  include Tenantable
  include MoneyInputs
  include VoucherSettleable
  include Partyable

  audited associated_with: :company

  money_input :amount_cents

  RECURRENCES = %w[one_time daily weekly monthly annually].freeze

  belongs_to :expense_category
  belongs_to :user
  belongs_to :treasury, optional: true
  belongs_to :source_record, polymorphic: true, optional: true

  has_one_attached :receipt_image

  has_one :vendor_invoice_payment, as: :source_record

  monetize :amount_cents

  validates :description, :expense_date, :amount_cents, presence: true
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :amount_cents, numericality: { greater_than: 0 }

  scope :manual, -> { where(is_auto_generated: false) }
  scope :auto_generated, -> { where(is_auto_generated: true) }
  scope :on_date_range, ->(start_date, end_date) {
    where(expense_date: start_date..end_date)
  }

  after_commit :sync_treasury_ledger, on: %i[create update]
  after_destroy :remove_treasury_ledger

  def self.ransackable_attributes(_auth_object = nil)
    %w[description expense_date amount_cents is_auto_generated expense_category_id treasury_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[expense_category user treasury]
  end

  private

  # Legacy only. A supplier payment used to write an Expense so that it showed
  # up as one, while the entry for it belonged to
  # JournalEntryService.record_vendor_invoice_payment! — which posts
  # DR Accounts Payable / CR cash, the whole double entry on its own. Such an
  # expense must post neither an entry nor a voucher: either would credit cash
  # twice and charge an expense account for goods already expensed to Purchases
  # (5100) when the invoice was received.
  #
  # Nothing writes one any more — a supplier payment is a voucher. But rows
  # written before that change are still in the books, and editing one has to
  # keep behaving. This goes when VendorInvoicePayment is dropped and those rows
  # are migrated.
  def ledger_owned_elsewhere?
    source_record_type == "VendorInvoicePayment"
  end

  def voucher_direction = Voucher::PAYMENT
  def settlement_date   = expense_date
  def settlement_date_changed? = saved_change_to_expense_date?

  # The expense no longer moves cash — a payment voucher does. All this writes
  # is the obligation.
  def sync_treasury_ledger
    return Accounting::TreasuryLedgerService.sync_expense_cash!(self) if ledger_owned_elsewhere?

    Accounting::JournalEntryService.record_expense!(self)
  end

  # Deleting takes the ledger with it. Keeping the journal entry after the record
  # is gone leaves the P&L reporting money against something nobody can open or
  # trace, and the cash flow — which reads the treasury — stops agreeing with it.
  # This is the only way to undo one: an edit rewrites the entry, a delete removes
  # it, and the audit log keeps what was there.
  def remove_treasury_ledger
    Accounting::TreasuryLedgerService.remove_source!(self)
    Accounting::JournalEntryService.destroy_for_source!(self)
  end
end
