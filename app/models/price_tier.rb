# frozen_string_literal: true

# A named pricing level for commercial customers — a blanket discount % off the
# base price. The "tier" half of tiers+override; a customer may also carry a
# per-customer override that wins over their tier.
class PriceTier < ApplicationRecord
  include Tenantable

  has_many :customers, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }
  validates :discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name discount_percent active position]
  end
end
