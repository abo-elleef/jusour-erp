# frozen_string_literal: true

class AddInventoryFinancePermissionToRoles < ActiveRecord::Migration[7.1]
  # Roles that should receive the new inventory:finance permission by default.
  FINANCE_ROLES = %w[owner super_manager accountant].freeze

  def up
    execute(<<~SQL)
      UPDATE roles
      SET permissions = permissions || '["inventory:finance"]'::jsonb
      WHERE key IN (#{FINANCE_ROLES.map { |k| "'#{k}'" }.join(', ')})
        AND NOT (permissions @> '["inventory:finance"]'::jsonb)
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE roles
      SET permissions = (
        SELECT jsonb_agg(elem)
        FROM jsonb_array_elements_text(permissions) AS elem
        WHERE elem <> 'inventory:finance'
      )
    SQL
  end
end
