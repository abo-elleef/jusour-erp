# frozen_string_literal: true

class AddCustomerPhonesAndAddresses < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :phone_secondary, :string
    add_index :customers, :phone_secondary, unique: true, where: "phone_secondary IS NOT NULL"

    create_table :customer_addresses, id: :uuid do |t|
      t.references :customer, type: :uuid, null: false, foreign_key: true
      t.string :label
      t.text :address, null: false
      t.boolean :is_default, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

  end
end
