# frozen_string_literal: true

class Expense < ApplicationRecord
  include Tenantable
  include MoneyInputs

  audited associated_with: :company

  money_input :amount_cents

  RECURRENCES = %w[one_time daily weekly monthly annually].freeze

  belongs_to :expense_category
  belongs_to :user
  belongs_to :treasury, optional: true
  belongs_to :source_record, polymorphic: true, optional: true

  has_one_attached :receipt_image

  # The vouchers that have settled this, and for how much. What is left is what
  # is still owed — the balance sitting on the accrual account.
  has_many :payment_allocations, as: :settles, dependent: :destroy

  has_one :vendor_invoice_payment, as: :source_record

  monetize :amount_cents

  validates :description, :expense_date, :amount_cents, presence: true
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :treasury, presence: true, unless: :is_auto_generated?

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

  def settled_cents
    payment_allocations.sum(:amount_cents)
  end

  def outstanding_cents
    amount_cents - settled_cents
  end

  private

  def sync_treasury_ledger
    Accounting::TreasuryLedgerService.sync_expense!(self)
    # Auto-generated expenses (vendor payments, direct AP) get their own JE via their services
    Accounting::JournalEntryService.record_expense!(self) unless is_auto_generated?
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
