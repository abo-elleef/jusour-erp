# frozen_string_literal: true

class FixedAsset < ApplicationRecord
  include Tenantable
  include MoneyInputs

  ASSET_TYPES = %w[equipment furniture vehicle property leasehold_improvement other].freeze

  belongs_to :location, optional: true
  belongs_to :recorded_by, class_name: "User"

  monetize :purchase_price_cents
  monetize :current_value_cents

  money_input :purchase_price_cents, :current_value_cents

  validates :name,                 presence: true
  validates :asset_type,           inclusion: { in: ASSET_TYPES }
  validates :purchase_date,        presence: true
  validates :purchase_price_cents, numericality: { greater_than: 0 }
  validates :current_value_cents,  numericality: { greater_than_or_equal_to: 0 }
  validates :useful_life_years,    numericality: { greater_than: 0 }, allow_nil: true

  scope :active,   -> { where(active: true) }
  scope :disposed, -> { where(active: false) }
  scope :ordered,  -> { order(:asset_type, :name) }
  scope :by_type,  ->(type) { where(asset_type: type) }

  def disposed?
    !active?
  end

  def depreciation_cents
    purchase_price_cents - current_value_cents
  end

  def depreciation_rate
    return 0 if purchase_price_cents.zero?

    ((depreciation_cents.to_f / purchase_price_cents) * 100).round(1)
  end
end
