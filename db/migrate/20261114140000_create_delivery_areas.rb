# frozen_string_literal: true

# The zones a branch delivers to for self-ordering, each with its own fee. The
# customer picks one at checkout; the fee is copied onto the order.
class CreateDeliveryAreas < ActiveRecord::Migration[7.1]
  def change
    create_table :delivery_areas, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :location, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :name_ar
      t.integer :fee_cents, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :delivery_areas, %i[location_id position]
  end
end
