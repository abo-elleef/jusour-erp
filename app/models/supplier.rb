# frozen_string_literal: true

class Supplier < ApplicationRecord
  include Tenantable
  include Accountable

  has_many :supplier_ingredients, dependent: :destroy
  has_many :ingredients, through: :supplier_ingredients
  has_many :vendor_invoices, dependent: :nullify
  has_many :supplier_price_histories, dependent: :nullify
  has_many :stock_batches, dependent: :nullify
  belongs_to :ap_treasury, class_name: "Treasury", foreign_key: :treasury_id, optional: true

  validates :name, presence: true

  scope :active, -> { where(active: true) }

  after_create :ensure_ap_treasury!

  def self.ransackable_attributes(_auth_object = nil)
    %w[name contact_name email phone active]
  end

  def ap_balance_cents
    ap_treasury&.balance_cents || 0
  end

  # Accountable — a supplier has nothing of its own to post against; its
  # account *is* its AP treasury's. Overrides the default template entirely
  # rather than defining account_code/account_name/etc. individually.
  def to_account
    ap_treasury&.to_account
  end

  # A supplier can be permanently deleted only when it carries no financial or
  # inventory history — otherwise deleting would orphan invoices, stock, or AP records.
  def deletable?
    deletion_blockers.empty?
  end

  def deletion_blockers
    blockers = []
    blockers << :vendor_invoices if vendor_invoices.exists?
    blockers << :stock_batches if stock_batches.exists?
    blockers << :price_histories if supplier_price_histories.exists?
    blockers << :ap_activity if ap_treasury_has_activity?
    blockers
  end

  def ap_treasury_has_activity?
    ap_treasury.present? &&
      (ap_treasury.balance_cents != 0 || ap_treasury.treasury_transactions.exists?)
  end

  def ensure_ap_treasury!
    return ap_treasury if ap_treasury.present?

    Accounting::SupplierApLedgerService.new(self).ensure_treasury!
  end
end
