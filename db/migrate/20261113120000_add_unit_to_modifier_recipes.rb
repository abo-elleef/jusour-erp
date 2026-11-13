# frozen_string_literal: true

# A modifier recipe's quantity was always in the ingredient's base unit, with no
# way to say "1 piece" of an ingredient stocked by the batch. Same optional unit
# as item recipes; existing rows stay null = base unit, so nothing changes until
# someone re-enters them.
class AddUnitToModifierRecipes < ActiveRecord::Migration[7.1]
  def change
    add_reference :modifier_recipes, :unit, type: :uuid, foreign_key: true, null: true
  end
end
