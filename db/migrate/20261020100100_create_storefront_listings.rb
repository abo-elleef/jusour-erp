# frozen_string_literal: true

# A product published on the storefront. Points at the ingredient the company
# already sells on invoices, and keeps the public-facing copy and photos off the
# operational model — most ingredients are raw materials that never go public.
class CreateStorefrontListings < ActiveRecord::Migration[7.1]
  def change
    create_table :storefront_listings, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :ingredient, null: false, foreign_key: true, type: :uuid, index: false
      t.string :slug, null: false
      t.string :title, null: false, default: ""
      t.text :description, null: false, default: ""
      t.boolean :published, null: false, default: true
      t.boolean :featured, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :storefront_listings, %i[company_id ingredient_id], unique: true
    add_index :storefront_listings, %i[company_id slug], unique: true
    add_index :storefront_listings, :ingredient_id
  end
end
