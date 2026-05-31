# frozen_string_literal: true

class Recipe < ApplicationRecord
  belongs_to :menu_item
  belongs_to :ingredient

  validates :quantity_used, numericality: { greater_than: 0 }
  validates :menu_item_id, uniqueness: { scope: :ingredient_id }
end
