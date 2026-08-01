# frozen_string_literal: true

class CreateDigitalWalletDayCloses < ActiveRecord::Migration[7.1]
  def change
    create_table :digital_wallet_day_closes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.date :business_date, null: false
      t.integer :instapay_statement_cents, null: false, default: 0
      t.integer :vodafone_cash_statement_cents, null: false, default: 0
      t.text :notes
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }, type: :uuid

      t.timestamps
    end

    add_index :digital_wallet_day_closes, %i[company_id business_date], unique: true,
              name: "index_digital_wallet_day_closes_on_company_and_date"
  end
end
