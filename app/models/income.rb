# frozen_string_literal: true

class Income < ApplicationRecord
  include Tenantable
  include MoneyInputs
  include VoucherSettleable
  include Partyable

  audited associated_with: :company

  money_input :amount_cents

  RECURRENCES = Expense::RECURRENCES

  belongs_to :income_category
  belongs_to :user
  belongs_to :treasury, optional: true
  belongs_to :source_record, polymorphic: true, optional: true

  has_one_attached :receipt_image

  monetize :amount_cents

  validates :description, :income_date, :amount_cents, presence: true
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :amount_cents, numericality: { greater_than: 0 }

  scope :manual, -> { where(is_auto_generated: false) }
  scope :auto_generated, -> { where(is_auto_generated: true) }
  scope :on_date_range, ->(start_date, end_date) {
    where(income_date: start_date..end_date)
  }

  after_commit :sync_treasury_ledger, on: %i[create update]
  after_destroy :remove_treasury_ledger

  def self.ransackable_attributes(_auth_object = nil)
    %w[description income_date amount_cents is_auto_generated income_category_id treasury_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[income_category user treasury]
  end

  private

  def voucher_direction = Voucher::RECEIPT
  def settlement_date   = income_date
  def settlement_date_changed? = saved_change_to_income_date?

  # The income no longer brings cash in — a receipt voucher does. All this
  # writes is the amount earned and owed to us.
  def sync_treasury_ledger
    Accounting::JournalEntryService.record_income!(self)
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
