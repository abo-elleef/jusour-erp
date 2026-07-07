# frozen_string_literal: true

# A measurement unit available to a company. Built-in units are seeded as
# `system` units; companies can add their own custom units on top.
class Unit < ApplicationRecord
  include Tenantable

  # Built-in units seeded for every company.
  DEFAULTS = %w[kg g lbs oz liters ml pieces packs gallons bales].freeze

  validates :name, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def deletable?
    !system?
  end

  # Seed the built-in units for a company (idempotent).
  def self.seed_defaults!(company)
    DEFAULTS.each_with_index do |name, i|
      company.units.where("LOWER(name) = ?", name).first ||
        company.units.create!(name: name, system: true, active: true, position: i)
    end
  end
end
