# frozen_string_literal: true

class TaxRate < ApplicationRecord
  include Taxable

  validates :name, :rate, :tax_category, presence: true
  validates :rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :tax_category, inclusion: { in: TAX_CATEGORIES }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:tax_category, :name) }

  def rate_percent
    return nil if rate.nil?

    (rate.to_d * 100).round(4)
  end

  def rate_percent=(value)
    self.rate = BigDecimal(value.to_s.presence || "0") / 100
  end
end
