# frozen_string_literal: true

# The storefront's info pages. Fixed slots only (About, Contact, Delivery &
# returns, Privacy) — no free-form pages or menus. Bodies are Action Text
# (`body` English, `body_ar` Arabic), sanitized by Rails when rendered.
class CreateStorefrontPages < ActiveRecord::Migration[7.1]
  def change
    create_table :storefront_pages, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :storefront, null: false, foreign_key: true, type: :uuid, index: false
      t.string :slot, null: false
      t.boolean :enabled, null: false, default: false
      t.string :title, null: false, default: ""
      t.string :title_ar, null: false, default: ""

      t.timestamps
    end

    add_index :storefront_pages, %i[storefront_id slot], unique: true
  end
end
