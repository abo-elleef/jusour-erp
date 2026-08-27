# frozen_string_literal: true

# Step 2 slice 1: distribution sales model foundation.
#   * price_tiers — named discount levels (blanket %), the "tier" in tiers+override
#   * customers gain a type (regular vs commercial), a tier link + per-customer
#     discount override, and two credit limits (soft warning / hard block) + terms
class AddCustomerTypesAndPriceTiers < ActiveRecord::Migration[7.1]
  def change
    create_table :price_tiers, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, index: true
      t.string :name, null: false
      t.decimal :discount_percent, precision: 5, scale: 2, default: "0.0", null: false
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :price_tiers, %i[company_id name], unique: true

    add_column :customers, :customer_type, :string, default: "regular", null: false
    add_reference :customers, :price_tier, type: :uuid, null: true, index: true
    add_column :customers, :discount_override_percent, :decimal, precision: 5, scale: 2
    add_column :customers, :credit_warning_limit_cents, :bigint
    add_column :customers, :credit_hard_limit_cents, :bigint
    add_column :customers, :credit_terms_days, :integer
  end
end
