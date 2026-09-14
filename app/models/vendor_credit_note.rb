# frozen_string_literal: true

# A purchase-return / supplier credit note. Created as a draft, then confirmed
# (see Inventory::ConfirmVendorCreditNoteService), which reduces the supplier's
# AP balance and posts a reversing journal entry (Dr AP / Cr Purchases).
class VendorCreditNote < ApplicationRecord
  include Tenantable

  STATUSES = %w[draft confirmed void].freeze

  # A goods return sends stock back to the supplier; a price adjustment (a rebate,
  # or a corrected price on goods we kept) only reduces what we owe. Both reverse
  # the purchase in the ledger — only the first moves inventory.
  KINDS = %w[goods_return price_adjustment].freeze

  belongs_to :supplier
  belongs_to :user
  belongs_to :location, optional: true
  # The invoice this credit comes off. Optional: a supplier can issue a standing
  # rebate that belongs to no single invoice, and that one only moves the supplier
  # balance. When it is set, confirming the note settles that invoice.
  belongs_to :vendor_invoice, optional: true
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
  validates :kind, inclusion: { in: KINDS }
  # Stock is location-scoped, so a return has to say where the goods left from.
  validates :location, presence: true, if: :goods_return?
  validate :invoice_belongs_to_supplier
  validate :credit_within_invoice_balance

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

  def goods_return?     = kind == "goods_return"
  def price_adjustment? = kind == "price_adjustment"

  def draft?     = status == "draft"
  def confirmed? = status == "confirmed"
  def void?      = status == "void"
  def postable?  = draft? && vendor_credit_note_lines.any?

  def subtotal_cents
    vendor_credit_note_lines.reject(&:marked_for_destruction?).sum(&:line_total_cents)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[credit_note_number credit_note_date status kind total_cents supplier_id location_id created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[supplier user location]
  end

  # What this note can still take off its invoice: the invoice's outstanding
  # balance, plus whatever this note has already applied (so re-validating a
  # confirmed note does not count its own credit against it).
  def invoice_headroom_cents
    return 0 if vendor_invoice.blank?

    vendor_invoice.balance_due_cents + applied_cents
  end

  def applied_cents
    confirmed? ? total_cents : 0
  end

  private

  def invoice_belongs_to_supplier
    return if vendor_invoice.blank? || supplier_id.blank?
    return if vendor_invoice.supplier_id == supplier_id

    errors.add(:vendor_invoice, :invalid)
  end

  # Without this a 2K credit on a 1K balance would drive the invoice — and the
  # supplier's AP balance — negative, which is the very thing the link prevents.
  def credit_within_invoice_balance
    return if vendor_invoice.blank? || void?
    return if subtotal_cents <= invoice_headroom_cents

    errors.add(:base, I18n.t("inventory.vendor_credit_notes.errors.exceeds_invoice_balance",
                             invoice_number: vendor_invoice.invoice_number,
                             default: "Credit is larger than the balance left on invoice #{vendor_invoice.invoice_number}"))
  end

  def recalculate_total
    self.total_cents = subtotal_cents
  end

  def assign_number
    return if credit_note_number.present?

    self.credit_note_number = self.class.next_number(company: company || Current.company)
  end
end
