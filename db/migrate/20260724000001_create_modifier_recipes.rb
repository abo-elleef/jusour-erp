# frozen_string_literal: true

class CreateModifierRecipes < ActiveRecord::Migration[7.1]
  def change
    create_table :modifier_recipes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :modifier,   null: false, foreign_key: true, type: :uuid
      t.references :ingredient, null: false, foreign_key: true, type: :uuid
      t.decimal    :quantity,   null: false, precision: 10, scale: 4
      t.uuid       :company_id, null: false

      t.timestamps
    end

    add_index :modifier_recipes, %i[modifier_id ingredient_id], unique: true
    add_index :modifier_recipes, :company_id
  end
end
