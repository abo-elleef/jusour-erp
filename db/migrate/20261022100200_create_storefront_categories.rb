# frozen_string_literal: true

# The public face of an inventory category: a photo, and display names and
# descriptions in English and Arabic. Optional — a category without a row here
# shows on the storefront under its inventory name with no photo.
class CreateStorefrontCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :storefront_categories, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :ingredient_category, null: false, foreign_key: true, type: :uuid, index: false
      t.string :title, null: false, default: ""
      t.string :title_ar, null: false, default: ""
      t.text :description, null: false, default: ""
      t.text :description_ar, null: false, default: ""

      t.timestamps
    end

    add_index :storefront_categories, %i[company_id ingredient_category_id], unique: true
    add_index :storefront_categories, :ingredient_category_id
  end
end
