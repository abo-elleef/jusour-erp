# frozen_string_literal: true

class CreateUnits < ActiveRecord::Migration[7.1]
  DEFAULTS = %w[kg g lbs oz liters ml pieces packs gallons bales].freeze

  def up
    create_table :units, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.boolean :system, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :units, %i[company_id name], unique: true

    # Seed the built-in units for every existing company so all current
    # ingredient/recipe/transfer unit values stay valid.
    say_with_time "Seeding default units for existing companies" do
      companies = select_all("SELECT id FROM companies").rows.flatten
      companies.each do |company_id|
        DEFAULTS.each_with_index do |name, i|
          execute(<<~SQL.squish)
            INSERT INTO units (id, company_id, name, active, system, position, created_at, updated_at)
            VALUES (gen_random_uuid(), '#{company_id}', '#{name}', true, true, #{i}, now(), now())
            ON CONFLICT (company_id, name) DO NOTHING
          SQL
        end
      end
      companies.size
    end
  end

  def down
    drop_table :units
  end
end
