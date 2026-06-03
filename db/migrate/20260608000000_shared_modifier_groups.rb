# frozen_string_literal: true

class SharedModifierGroups < ActiveRecord::Migration[7.1]
  def up
    create_table :menu_item_modifier_groups, id: :uuid do |t|
      t.references :menu_item, null: false, foreign_key: true, type: :uuid
      t.references :modifier_group, null: false, foreign_key: true, type: :uuid
      t.integer :position
      t.timestamps
    end

    add_index :menu_item_modifier_groups,
              %i[menu_item_id modifier_group_id],
              unique: true,
              name: "index_menu_item_modifier_groups_unique"

    execute <<~SQL.squish
      INSERT INTO menu_item_modifier_groups (id, menu_item_id, modifier_group_id, position, created_at, updated_at)
      SELECT gen_random_uuid(), menu_item_id, id, position, created_at, updated_at
      FROM modifier_groups
      WHERE menu_item_id IS NOT NULL
    SQL

    remove_foreign_key :modifier_groups, :menu_items
    remove_column :modifier_groups, :menu_item_id
  end

  def down
    add_reference :modifier_groups, :menu_item, null: true, foreign_key: true, type: :uuid

    execute <<~SQL.squish
      UPDATE modifier_groups mg
      SET menu_item_id = j.menu_item_id
      FROM (
        SELECT DISTINCT ON (modifier_group_id) modifier_group_id, menu_item_id
        FROM menu_item_modifier_groups
        ORDER BY modifier_group_id, position NULLS LAST, created_at
      ) j
      WHERE mg.id = j.modifier_group_id
    SQL

    change_column_null :modifier_groups, :menu_item_id, false
    drop_table :menu_item_modifier_groups
  end
end
