# frozen_string_literal: true

class CreatePaymentMethodTreasuries < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_method_treasuries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :payment_method, null: false
      t.references :treasury, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :payment_method_treasuries, %i[company_id payment_method], unique: true
  end
end
