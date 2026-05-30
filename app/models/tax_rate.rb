# frozen_string_literal: true

class TaxRate < ApplicationRecord
  validates :name, :rate, :tax_category, presence: true
  validates :rate, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
end
