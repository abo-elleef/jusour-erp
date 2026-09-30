# frozen_string_literal: true

class Loan < ApplicationRecord
  include Tenantable
  include Accountable

  ACCOUNT_CODE_BASE    = 2100
  INTEREST_EXPENSE_CODE = 5600

  LOAN_TYPES = %w[bank_loan investor_loan shareholder_loan equipment_financing other].freeze

  validates :name,           presence: true
  validates :loan_type,      inclusion: { in: LOAN_TYPES }
  validates :account_code,   presence: true, uniqueness: { scope: :company_id }
  validates :principal_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :installments_total, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:account_code) }

  before_validation :assign_account_code, on: :create

  def account_name
    "#{name} — قرض"
  end

  def outstanding_balance_cents
    account_lines.sum(:credit_cents) - account_lines.sum(:debit_cents)
  end

  # No credit or debit has ever posted against this loan's account — neither a
  # disbursement, an opening balance, nor a repayment. Only in this state is it
  # safe to seed an opening balance instead of a disbursement: recording one
  # once real activity exists would double up whatever was already posted.
  def ledger_untouched?
    !account_lines.exists?
  end

  # A repayment is the only thing that debits the loan's own account —
  # disbursement and opening balance both credit it, and interest posts to the
  # interest expense account instead, never here.
  def payments_made_count
    account_lines.where("debit_cents > 0").count
  end

  def payments_remaining_count
    return nil if installments_total.blank?

    [installments_total - payments_made_count, 0].max
  end

  def account_type = "liability"
  def normal_balance = :credit

  private

  def account_lines
    JournalEntryLine.joins(:journal_entry)
                    .where(journal_entries: { company_id: company_id })
                    .where(account_code: account_code)
  end

  def assign_account_code
    last = self.class.where(company_id: company_id).maximum(:account_code) || ACCOUNT_CODE_BASE
    self.account_code = last + 1
  end
end
