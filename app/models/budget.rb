# frozen_string_literal: true

class Budget < ApplicationRecord
  belongs_to :expense_category

  monetize :amount_cents

  validates :year, :month, presence: true
  validates :month, inclusion: { in: 1..12 }
  validates :expense_category_id, uniqueness: { scope: %i[year month] }
end
