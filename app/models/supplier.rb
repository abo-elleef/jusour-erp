# frozen_string_literal: true

class Supplier < ApplicationRecord
  include Tenantable

  has_many :supplier_ingredients, dependent: :destroy
  has_many :ingredients, through: :supplier_ingredients
  has_many :vendor_invoices, dependent: :nullify
  has_many :supplier_price_histories, dependent: :nullify
  has_many :stock_batches, dependent: :nullify

  validates :name, presence: true

  scope :active, -> { where(active: true) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name contact_name email phone active]
  end
end
