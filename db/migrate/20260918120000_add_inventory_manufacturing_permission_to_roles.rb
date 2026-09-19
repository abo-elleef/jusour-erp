# frozen_string_literal: true

class AddInventoryManufacturingPermissionToRoles < ActiveRecord::Migration[7.1]
  # The inventory manufacturing (production) tab gets its own key. Roles that
  # keep it by default: owner, super_manager, manager, accountant. Every other
  # role — sub_manager included — loses the tab until an owner grants it.
  ROLES = %w[owner super_manager manager accountant].freeze

  def up
    execute(<<~SQL)
      UPDATE roles
      SET permissions = permissions || '["inventory:manufacturing"]'::jsonb
      WHERE key IN ('#{ROLES.join("', '")}')
        AND NOT (permissions @> '["inventory:manufacturing"]'::jsonb)
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE roles
      SET permissions = (
        SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
        FROM jsonb_array_elements_text(permissions) AS elem
        WHERE elem <> 'inventory:manufacturing'
      )
    SQL
  end
end
