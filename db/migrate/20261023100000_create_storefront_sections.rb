# frozen_string_literal: true

# The storefront home page as an ordered list of predefined blocks (hero,
# featured products, text + image, …). `settings` holds each block's options;
# StorefrontSection::TYPES is the schema that decides which keys a block may
# have, so nothing free-form is stored. A storefront with no rows renders the
# default layout.
class CreateStorefrontSections < ActiveRecord::Migration[7.1]
  def change
    create_table :storefront_sections, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid, index: false
      t.references :storefront, null: false, foreign_key: true, type: :uuid, index: false
      t.string :section_type, null: false
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :storefront_sections, %i[storefront_id position]
    add_index :storefront_sections, :company_id
  end
end
