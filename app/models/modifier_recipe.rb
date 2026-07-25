# frozen_string_literal: true

class ModifierRecipe < ApplicationRecord
  include Tenantable

  belongs_to :modifier
  belongs_to :ingredient

  validates :quantity, numericality: { other_than: 0 }
  validates :modifier_id, uniqueness: { scope: :ingredient_id }
end
