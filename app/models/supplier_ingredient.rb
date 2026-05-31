# frozen_string_literal: true

class SupplierIngredient < ApplicationRecord
  belongs_to :supplier
  belongs_to :ingredient

  monetize :price_cents

  validates :ingredient_id, uniqueness: { scope: :supplier_id }

  before_save :clear_other_preferred_links, if: :preferred?

  private

  def clear_other_preferred_links
    ingredient.supplier_ingredients.where.not(id: id).update_all(preferred: false)
  end
end
