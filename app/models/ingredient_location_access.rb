# frozen_string_literal: true

# Join between an ingredient and the locations it's scoped to. Only consulted
# when the ingredient is NOT `all_locations` — see UserLocation for the same
# pattern applied to staff.
class IngredientLocationAccess < ApplicationRecord
  belongs_to :ingredient
  belongs_to :location

  validates :location_id, uniqueness: { scope: :ingredient_id }
end
