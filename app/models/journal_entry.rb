# frozen_string_literal: true

class JournalEntry < ApplicationRecord
  include Tenantable

  ENTRY_TYPES = %w[auto manual].freeze

  belongs_to :created_by, class_name: "User"
  has_many   :lines, class_name: "JournalEntryLine", dependent: :destroy
  accepts_nested_attributes_for :lines

  belongs_to :source_record, polymorphic: true, optional: true

  # Numbers are generated per company (see .next_entry_number), so uniqueness is
  # scoped the same way — a global scope collided across tenants.
  validates :entry_number, presence: true, uniqueness: { scope: :company_id }
  validates :date,         presence: true
  validates :description,  presence: true
  validates :entry_type,   inclusion: { in: ENTRY_TYPES }

  validate :lines_must_balance, if: -> { lines.any? }

  scope :ordered,       -> { order(date: :desc, entry_number: :desc) }
  scope :on_date_range, ->(from, to) { where(date: from..to) }
  scope :by_type,       ->(t) { where(entry_type: t) }
  scope :for_source,    ->(record) { where(source_record_type: record.class.name, source_record_id: record.id) }

  def total_debits_cents  = lines.sum(&:debit_cents)
  def total_credits_cents = lines.sum(&:credit_cents)
  def balanced?           = total_debits_cents == total_credits_cents
  def auto?               = entry_type == "auto"
  def manual?             = entry_type == "manual"

  # Reads the highest sequence among *this year's* numbers, rather than trusting
  # the lexical maximum to be one. Any entry number outside the pattern — an
  # import, a fixture, anything hand-written — used to win the `maximum` and send
  # the count back to 00001, colliding with the entry already holding it. That
  # mattered little while one action wrote one entry; an expense and its voucher
  # write two.
  #
  # Same shape as CustomerInvoice.next_invoice_number and Voucher.next_number.
  def self.next_entry_number(company_id)
    prefix = "JE-#{Date.current.year}-"

    max_seq = where(company_id: company_id)
      .where("entry_number ~ ?", "^#{prefix}[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(entry_number FROM #{prefix.length + 1}) AS INTEGER)"))

    format("%s%05d", prefix, (max_seq || 0) + 1)
  end

  private

  def lines_must_balance
    return if total_debits_cents == total_credits_cents
    errors.add(:base, "Journal entry is not balanced (debits #{total_debits_cents} ≠ credits #{total_credits_cents})")
  end
end
