# frozen_string_literal: true

class CreateMenuPromosAndComboSchedule < ActiveRecord::Migration[7.1]
  def change
    create_table :menu_promos, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :menu_item, null: false, foreign_key: true, type: :uuid
      t.references :location, null: true, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.integer :promo_price_cents, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :highlight, null: false, default: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :menu_promos, %i[company_id starts_at ends_at]
    add_index :menu_promos, %i[menu_item_id starts_at ends_at]

    add_column :combos, :starts_at, :datetime
    add_column :combos, :ends_at, :datetime
    add_column :combos, :highlight, :boolean, null: false, default: false

    add_reference :order_discounts, :menu_promo, type: :uuid, foreign_key: true, null: true
    add_reference :order_discounts, :order_item, type: :uuid, foreign_key: true, null: true
  end
end
