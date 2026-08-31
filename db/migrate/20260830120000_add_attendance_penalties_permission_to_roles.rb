# frozen_string_literal: true

class AddAttendancePenaltiesPermissionToRoles < ActiveRecord::Migration[7.1]
  # Roles that should review/waive late penalties: owner, super_manager, manager, accountant.
  # sub_manager logs attendance but does not review penalties.
  ROLES = %w[owner super_manager manager accountant].freeze

  def up
    execute(<<~SQL)
      UPDATE roles
      SET permissions = permissions || '["attendance:penalties"]'::jsonb
      WHERE key IN ('#{ROLES.join("', '")}')
        AND NOT (permissions @> '["attendance:penalties"]'::jsonb)
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE roles
      SET permissions = (
        SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
        FROM jsonb_array_elements_text(permissions) AS elem
        WHERE elem <> 'attendance:penalties'
      )
    SQL
  end
end
