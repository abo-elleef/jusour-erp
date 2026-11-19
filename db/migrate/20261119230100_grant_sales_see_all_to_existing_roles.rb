# frozen_string_literal: true

# New permission sales:see_all — without it, a user in the sales/leads area
# sees only their own leads, customers and invoices (Sales::OwnershipScope).
#
# Deploying must change nothing for anyone, so every existing role that can
# reach any part of that area today gets it. The owner then takes it away from
# the sales-rep role.
#
# Raw SQL on purpose (no app models in migrations); Roles::Seeder never
# backfills new keys into roles a company already has.
class GrantSalesSeeAllToExistingRoles < ActiveRecord::Migration[7.1]
  SALES_AREA_KEYS = %w[customers:manage leads:view sales:confirm_payments sales:dispatch sales:complete_shipping].freeze

  def up
    any_sales_key = SALES_AREA_KEYS.map { |key| "'#{key}'" }.join(", ")
    execute <<~SQL.squish
      UPDATE roles SET permissions = permissions || '["sales:see_all"]'::jsonb, updated_at = NOW()
      WHERE permissions ?| ARRAY[#{any_sales_key}]
        AND NOT permissions @> '["sales:see_all"]'::jsonb
    SQL
  end

  def down
    execute "UPDATE roles SET permissions = permissions - 'sales:see_all'"
  end
end
