# frozen_string_literal: true

# New permission orders:complete_unpaid. Without it a POS user completes only
# fully paid orders (OrderPolicy#complete?), so cashiers can no longer close an
# order that still owes money. Roles that run the floor today (they refund
# orders or manage the menu: owner, super manager, manager, sub-manager) keep
# completing unpaid orders as before. Raw SQL on purpose (no app models in
# migrations); Roles::Seeder never backfills new keys into existing roles.
class GrantCompleteUnpaidToExistingRoles < ActiveRecord::Migration[7.1]
  KEY = "orders:complete_unpaid"

  def up
    execute <<~SQL.squish
      UPDATE roles SET permissions = permissions || '["#{KEY}"]'::jsonb, updated_at = NOW()
      WHERE permissions ?| ARRAY['orders:refund', 'menu:manage']
        AND NOT permissions @> '["#{KEY}"]'::jsonb
    SQL
  end

  def down
    execute "UPDATE roles SET permissions = permissions - '#{KEY}'"
  end
end
