# frozen_string_literal: true

# A short, human-readable reference code for each menu item (like a journal
# entry's "Entry #"). Auto-assigned per company, editable into a custom SKU.
class AddCodeToMenuItems < ActiveRecord::Migration[7.1]
  def up
    add_column :menu_items, :code, :string

    # Backfill existing items with MI-0001… per company, in creation order.
    execute <<~SQL.squish
      UPDATE menu_items SET code = sub.code FROM (
        SELECT id,
               'MI-' || LPAD(
                 (ROW_NUMBER() OVER (PARTITION BY company_id ORDER BY created_at, id))::text,
                 4, '0'
               ) AS code
        FROM menu_items
      ) sub
      WHERE menu_items.id = sub.id
    SQL

    change_column_null :menu_items, :code, false
    add_index :menu_items, "company_id, lower(code)", unique: true, name: "index_menu_items_on_company_and_lower_code"
  end

  def down
    remove_index :menu_items, name: "index_menu_items_on_company_and_lower_code"
    remove_column :menu_items, :code
  end
end
