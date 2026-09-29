# frozen_string_literal: true

# A customer credit note / sales return. Built as a draft, then confirmed (see
# Sales::ConfirmCreditNoteService), which reduces AR and optionally restocks the
# returned goods.
class CreditNote < ApplicationRecord
  include Tenantable

  # historical = a return that happened before this system (see CustomerInvoice).
  # Counted by sales reporting, invisible to the ledger and to stock.
  STATUSES = %w[draft confirmed historical void].freeze

  belongs_to :customer
  belongs_to :user
  belongs_to :location
  belongs_to :customer_invoice, optional: true
  has_many :credit_note_lines, -> { order(:position, :created_at) },
    dependent: :destroy, inverse_of: :credit_note

  accepts_nested_attributes_for :credit_note_lines, allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  monetize :total_cents

  validates :credit_note_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :credit_note_number, presence: true,
    uniqueness: { scope: :company_id, case_sensitive: false }

  before_validation :assign_number, on: :create
  before_save :recalculate_total

  scope :confirmed, -> { where(status: "confirmed") }
  scope :historical, -> { where(status: "historical") }
  scope :realized, -> { where(status: %w[confirmed historical]) }
  scope :recent, -> { order(credit_note_date: :desc, created_at: :desc) }

  def self.next_number(company: Current.company, year: Date.current.year)
    prefix = "CN-#{year}-"
    return "#{prefix}00001" if company.blank?

    max_seq = unscoped_by_company
      .where(company_id: company.id)
      .where("credit_note_number ~ ?", "^CN-#{year}-[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(credit_note_number FROM #{prefix.length + 1}) AS INTEGER)"))

    format("%s%05d", prefix, (max_seq || 0) + 1)
  end

  def draft?      = status == "draft"
  def confirmed?  = status == "confirmed"
  def historical? = status == "historical"
  def void?       = status == "void"

  def subtotal_cents
    credit_note_lines.reject(&:marked_for_destruction?).sum(&:line_total_cents)
  end

  private

  def recalculate_total
    self.total_cents = subtotal_cents
  end

  def assign_number
    return if credit_note_number.present?

    self.credit_note_number = self.class.next_number(company: company || Current.company)
  end
end
