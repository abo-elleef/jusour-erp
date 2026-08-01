# frozen_string_literal: true

class AddBusinessDayModeAndLocationOperatingDays < ActiveRecord::Migration[7.1]
  def change
    add_column :company_settings, :business_day_mode, :string, null: false, default: "automatic"

    create_table :location_operating_days, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :location, null: false, foreign_key: true, type: :uuid
      t.date :business_date, null: false
      t.datetime :opened_at, null: false
      t.references :opened_by, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :closed_at
      t.references :closed_by, null: true, foreign_key: { to_table: :users }, type: :uuid

      t.timestamps
    end

    add_index :location_operating_days, %i[location_id],
              unique: true,
              where: "closed_at IS NULL",
              name: "index_location_operating_days_one_open_per_location"
    add_index :location_operating_days, %i[company_id location_id business_date]

    add_reference :cash_drawer_sessions, :location, type: :uuid, null: true, foreign_key: true, index: true

    add_reference :digital_wallet_day_closes, :location, type: :uuid, null: true, foreign_key: true, index: true
    remove_index :digital_wallet_day_closes, name: "index_digital_wallet_day_closes_on_company_and_date"
    add_index :digital_wallet_day_closes, %i[company_id business_date location_id],
              unique: true,
              name: "index_digital_wallet_day_closes_on_company_date_location"
  end
end
