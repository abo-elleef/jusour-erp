# frozen_string_literal: true

# A purchase-return / supplier credit note. Created as a draft, then confirmed
# (see Inventory::ConfirmVendorCreditNoteService), which reduces the supplier's
# AP balance and posts a reversing journal entry (Dr AP / Cr Purchases).
class VendorCreditNote < ApplicationRecord
  include Tenantable

  STATUSES = %w[draft confirmed void].freeze

  belongs_to :supplier
  belongs_to :user
  has_many :vendor_credit_note_lines,
    -> { order(:position, :created_at) },
    dependent: :destroy,
    inverse_of: :vendor_credit_note

  accepts_nested_attributes_for :vendor_credit_note_lines,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  monetize :total_cents

  validates :credit_note_number, presence: true,
    uniqueness: { scope: :company_id, case_sensitive: false }
  validates :credit_note_date, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :assign_number, on: :create
  before_save :recalculate_total

  scope :drafts,    -> { where(status: "draft") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :recent,    -> { order(credit_note_date: :desc, created_at: :desc) }

  def self.next_number(company: Current.company, year: Date.current.year)
    prefix = "VCN-#{year}-"
    return "#{prefix}00001" if company.blank?

    max_seq = unscoped_by_company
      .where(company_id: company.id)
      .where("credit_note_number ~ ?", "^VCN-#{year}-[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(credit_note_number FROM #{prefix.length + 1}) AS INTEGER)"))

    format("%s%05d", prefix, (max_seq || 0) + 1)
  end

  def draft?     = status == "draft"
  def confirmed? = status == "confirmed"
  def void?      = status == "void"
  def postable?  = draft? && vendor_credit_note_lines.any?

  def subtotal_cents
    vendor_credit_note_lines.reject(&:marked_for_destruction?).sum(&:line_total_cents)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[credit_note_number credit_note_date status total_cents supplier_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[supplier user]
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
