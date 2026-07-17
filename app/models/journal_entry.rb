# frozen_string_literal: true

class JournalEntry < ApplicationRecord
  include Tenantable

  ENTRY_TYPES = %w[auto manual].freeze

  belongs_to :created_by, class_name: "User"
  has_many   :lines, class_name: "JournalEntryLine", dependent: :destroy
  accepts_nested_attributes_for :lines

  validates :entry_number, presence: true, uniqueness: true
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

  def self.next_entry_number(company_id)
    last = where(company_id: company_id).maximum(:entry_number)
    year = Date.current.year
    if last&.start_with?("JE-#{year}-")
      seq = last.split("-").last.to_i + 1
    else
      seq = 1
    end
    "JE-#{year}-#{seq.to_s.rjust(5, '0')}"
  end

  private

  def lines_must_balance
    return if total_debits_cents == total_credits_cents
    errors.add(:base, "Journal entry is not balanced (debits #{total_debits_cents} ≠ credits #{total_credits_cents})")
  end
end
