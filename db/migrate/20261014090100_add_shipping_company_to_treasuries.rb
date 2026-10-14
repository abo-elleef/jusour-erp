# frozen_string_literal: true

class AddShippingCompanyToTreasuries < ActiveRecord::Migration[7.1]
  def change
    add_column :treasuries, :shipping_company_id, :uuid
    add_index :treasuries, :shipping_company_id
  end
end
