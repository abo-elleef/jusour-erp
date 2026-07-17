# frozen_string_literal: true

class JournalEntryLine < ApplicationRecord
  ACCOUNT_TYPES = %w[asset liability equity revenue expense].freeze

  belongs_to :journal_entry
  belongs_to :treasury, optional: true

  attr_accessor :account_encoded, :debit_pounds, :credit_pounds

  validates :account_code,  presence: true, numericality: { only_integer: true }
  validates :account_name,  presence: true
  validates :account_type,  inclusion: { in: ACCOUNT_TYPES }
  validates :debit_cents,   numericality: { greater_than_or_equal_to: 0 }
  validates :credit_cents,  numericality: { greater_than_or_equal_to: 0 }
  validate  :exactly_one_side_nonzero

  scope :debits,  -> { where("debit_cents > 0") }
  scope :credits, -> { where("credit_cents > 0") }

  private

  def exactly_one_side_nonzero
    if debit_cents.to_i.zero? && credit_cents.to_i.zero?
      errors.add(:base, "Line must have a debit or credit amount")
    elsif debit_cents.to_i.positive? && credit_cents.to_i.positive?
      errors.add(:base, "Line cannot have both debit and credit")
    end
  end
end
