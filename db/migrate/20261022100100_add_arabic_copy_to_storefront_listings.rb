# frozen_string_literal: true

# Arabic versions of a listing's public title and description. `title` and
# `description` hold the English version.
class AddArabicCopyToStorefrontListings < ActiveRecord::Migration[7.1]
  def change
    change_table :storefront_listings, bulk: true do |t|
      t.string :title_ar, null: false, default: ""
      t.text :description_ar, null: false, default: ""
    end
  end
end
