# frozen_string_literal: true

class CreateWorkstations < ActiveRecord::Migration[7.1]
  def change
    create_table :workstations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :location, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.references :receipt_printer, null: true, foreign_key: { to_table: :printers }, type: :uuid

      t.timestamps
    end

    add_index :workstations, %i[location_id name], unique: true
    add_index :workstations, %i[company_id active]

    add_reference :orders, :workstation, type: :uuid, null: true, foreign_key: true, index: true
  end
end
