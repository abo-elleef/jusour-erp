class CreatePartners < ActiveRecord::Migration[7.1]
  def change
    create_table :partners, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string  :name,                 null: false
      t.integer :account_code,         null: false
      t.decimal :ownership_percentage, null: false, precision: 5, scale: 2
      t.boolean :active,               null: false, default: true
      t.text    :notes

      t.timestamps
    end

    add_index :partners, [:company_id, :account_code], unique: true
  end
end
