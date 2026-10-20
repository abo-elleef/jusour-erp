# frozen_string_literal: true

# A company's public product catalog website (the distribution vertical's
# "Shopify-style" storefront). One per company. Reached at /s/:company_slug and,
# once `subdomain` is set, at <subdomain>.<STOREFRONT_DOMAIN>.
class CreateStorefronts < ActiveRecord::Migration[7.1]
  def change
    create_table :storefronts, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :subdomain
      t.string :tagline, null: false, default: ""
      t.text :about, null: false, default: ""
      t.string :phone, null: false, default: ""
      t.string :whatsapp_number, null: false, default: ""
      t.string :email, null: false, default: ""
      t.string :address, null: false, default: ""
      t.boolean :show_prices, null: false, default: true
      t.string :seo_description, null: false, default: ""

      t.timestamps
    end

    add_index :storefronts, "lower(subdomain)", unique: true, where: "subdomain IS NOT NULL",
      name: "index_storefronts_on_lower_subdomain"
  end
end
