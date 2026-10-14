# frozen_string_literal: true

# A courier used on delivery customer invoices. For cash-on-delivery
# shipments they collect the customer's cash and owe it to us until they
# remit it — tracked the same way a Customer's AR is: a lazily-created
# ledger treasury whose balance is what they currently owe.
class ShippingCompany < ApplicationRecord
  include Tenantable
  include Accountable

  belongs_to :ar_treasury, class_name: "Treasury", foreign_key: :treasury_id, optional: true
  has_many :customer_invoices, dependent: :restrict_with_error

  INDEX_SORTABLE_COLUMNS = %w[name balance active created_at].freeze
  INDEX_DEFAULT_SORT = "name"
  INDEX_DEFAULT_SORT_DIRECTION = "asc"

  validates :name, presence: true, uniqueness: { scope: :company_id }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  # Amount this shipping company currently owes us (0 when nothing has
  # dispatched through them yet).
  def balance_cents
    ar_treasury&.balance_cents || 0
  end

  # A shipping company can be permanently deleted only when no invoice has ever
  # been dispatched through them and their ledger (if one exists) has no
  # history — otherwise deleting would orphan invoices or lose paid-down AR
  # history. Mirrors Supplier#deletable?/#ap_treasury_has_activity?.
  def deletable?
    deletion_blockers.empty?
  end

  def deletion_blockers
    blockers = []
    blockers << :customer_invoices if customer_invoices.exists?
    blockers << :ar_activity if ar_treasury_has_activity?
    blockers
  end

  def ar_treasury_has_activity?
    ar_treasury.present? &&
      (ar_treasury.balance_cents != 0 || ar_treasury.treasury_transactions.exists?)
  end

  # Accountable — see Customer#to_account: a shipping company's account is
  # its own ledger treasury's, not anything of its own.
  def to_account
    ar_treasury&.to_account
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name phone active created_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
