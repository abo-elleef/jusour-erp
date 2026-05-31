# frozen_string_literal: true

class SupplierPriceHistory < ApplicationRecord
  belongs_to :supplier
  belongs_to :ingredient
  belongs_to :recorded_by_user, class_name: "User", optional: true

  monetize :price_cents

  validates :effective_date, presence: true
end
