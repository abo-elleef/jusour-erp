class Partner < ApplicationRecord
  include Tenantable

  ACCOUNT_CODE_BASE = 3100

  validates :name, presence: true
  validates :ownership_percentage,
            numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :account_code, presence: true, uniqueness: { scope: :company_id }

  scope :active,   -> { where(active: true) }
  scope :ordered,  -> { order(:account_code) }

  before_validation :assign_account_code, on: :create

  def account_name
    "#{name} — حساب جاري"
  end

  def balance_cents
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
