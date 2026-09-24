# frozen_string_literal: true

# Mirrors the user/location scoping (see AddLocationScopingToUsers): an
# ingredient works everywhere by default, and can be scoped down to specific
# locations by turning `all_locations` off and picking which ones apply.
#
# `ingredient_locations` was already taken — it's the per-location stock
# ledger (quantity_on_hand, reorder_threshold, max_quantity), created lazily
# whenever an ingredient is actually stocked somewhere. This is a separate,
# unrelated concept: which locations the ingredient is allowed at, regardless
# of whether stock has ever moved there.
class AddLocationScopingToIngredients < ActiveRecord::Migration[7.1]
  def change
    add_column :ingredients, :all_locations, :boolean, default: true, null: false

    create_table :ingredient_location_accesses, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :ingredient_id, null: false
      t.uuid :location_id, null: false
      t.timestamps
    end
    add_index :ingredient_location_accesses, %i[ingredient_id location_id], unique: true,
      name: "index_ingredient_location_accesses_on_ingredient_and_location"
    add_index :ingredient_location_accesses, :location_id
    add_foreign_key :ingredient_location_accesses, :ingredients
    add_foreign_key :ingredient_location_accesses, :locations
  end
end
