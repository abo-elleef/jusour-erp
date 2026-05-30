# frozen_string_literal: true

module Taxable
  extend ActiveSupport::Concern

  TAX_CATEGORIES = %w[food beverage packaged].freeze

  included do
    validates :tax_category, inclusion: { in: TAX_CATEGORIES }, allow_nil: true
  end
end
