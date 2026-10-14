# frozen_string_literal: true

# A courier the distribution vertical hands cash-on-delivery shipments to.
# They collect cash from the customer and remit it to us later, so they carry
# a running balance the same shape as a Customer's AR — see ShippingCompany
# and Accounting::ShippingCompanyLedgerService.
class CreateShippingCompanies < ActiveRecord::Migration[7.1]
  def change
    create_table :shipping_companies, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.uuid :treasury_id
      t.string :phone
      t.text :notes
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :shipping_companies, :treasury_id
    add_index :shipping_companies, %i[company_id name], unique: true
  end
end
