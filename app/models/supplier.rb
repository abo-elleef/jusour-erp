# frozen_string_literal: true

class Supplier < ApplicationRecord
  include Tenantable

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

  def ensure_ap_treasury!
    return ap_treasury if ap_treasury.present?

    Accounting::SupplierApLedgerService.new(self).ensure_treasury!
  end
end
