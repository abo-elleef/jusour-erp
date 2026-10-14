# frozen_string_literal: true

# Company-configurable online payment methods for the Sales module (InstaPay,
# bank transfer, a particular mobile wallet, ...) — deliberately separate
# from PaymentMethodTreasury/Payment::DIGITAL_WALLET_METHODS, which is shared
# POS day-close infrastructure this feature must not touch.
class CreateSalesPaymentMethods < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_payment_methods, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.uuid :treasury_id, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :sales_payment_methods, :treasury_id
    add_index :sales_payment_methods, %i[company_id name], unique: true
  end
end
