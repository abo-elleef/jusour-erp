# frozen_string_literal: true

class Loan < ApplicationRecord
  include Tenantable

  ACCOUNT_CODE_BASE    = 2100
  INTEREST_EXPENSE_CODE = 5600

  LOAN_TYPES = %w[bank_loan investor_loan shareholder_loan equipment_financing other].freeze

  validates :name,           presence: true
  validates :loan_type,      inclusion: { in: LOAN_TYPES }
  validates :account_code,   presence: true, uniqueness: { scope: :company_id }
  validates :principal_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:account_code) }

  before_validation :assign_account_code, on: :create

  def account_name
    "#{name} — قرض"
  end

  def outstanding_balance_cents
    lines = JournalEntryLine.joins(:journal_entry)
                            .where(journal_entries: { company_id: company_id })
                            .where(account_code: account_code)
    lines.sum(:credit_cents) - lines.sum(:debit_cents)
  end

  private

  def assign_account_code
    last = self.class.where(company_id: company_id).maximum(:account_code) || ACCOUNT_CODE_BASE
    self.account_code = last + 1
  end
end
