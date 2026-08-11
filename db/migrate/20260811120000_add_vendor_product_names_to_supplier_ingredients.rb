# frozen_string_literal: true

class AddVendorProductNamesToSupplierIngredients < ActiveRecord::Migration[7.1]
  def change
    add_column :supplier_ingredients, :vendor_product_name, :string
    add_column :supplier_ingredients, :vendor_sku, :string
  end
end
