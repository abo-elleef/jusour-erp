# frozen_string_literal: true

# Two new permissions gate the shipping track:
#   sales:dispatch          — hand a delivery to the courier ("shipped").
#   sales:complete_shipping — confirm the courier delivered it.
#
# Until now anyone who could reach the sales area (customers:manage) could
# dispatch, so every existing role with customers:manage keeps that ability.
# Completion is new: it starts with the owner, super manager and manager
# built-ins; the owner hands it to whoever checks the courier's system.
#
# Raw SQL on purpose (no app models in migrations); Roles::Seeder never
# backfills new keys into roles a company already has.
class GrantShippingPermissionsToExistingRoles < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE roles SET permissions = permissions || '["sales:dispatch"]'::jsonb, updated_at = NOW()
      WHERE permissions @> '["customers:manage"]'::jsonb
        AND NOT permissions @> '["sales:dispatch"]'::jsonb
    SQL

    execute <<~SQL.squish
      UPDATE roles SET permissions = permissions || '["sales:complete_shipping"]'::jsonb, updated_at = NOW()
      WHERE key IN ('owner', 'super_manager', 'manager')
        AND NOT permissions @> '["sales:complete_shipping"]'::jsonb
    SQL
  end

  def down
    execute "UPDATE roles SET permissions = permissions - 'sales:dispatch' - 'sales:complete_shipping'"
  end
end
