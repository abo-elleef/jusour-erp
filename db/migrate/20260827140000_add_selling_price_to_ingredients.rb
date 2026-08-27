# frozen_string_literal: true

# A suggested selling price per product — a guide for sales when building customer
# invoices (prefills the line's unit price; still editable).
class AddSellingPriceToIngredients < ActiveRecord::Migration[7.1]
  def change
    add_column :ingredients, :selling_price_cents, :bigint, default: 0, null: false
  end
end
