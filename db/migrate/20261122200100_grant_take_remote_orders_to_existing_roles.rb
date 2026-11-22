# frozen_string_literal: true

# New permission orders:take_remote (send call-center orders to a branch). The
# owner and super manager roles get every key by default, so existing companies'
# copies of those roles get it too. Other roles are left for the owner to decide.
# Raw SQL on purpose (no app models in migrations).
class GrantTakeRemoteOrdersToExistingRoles < ActiveRecord::Migration[7.1]
  KEY = "orders:take_remote"

  def up
    execute <<~SQL.squish
      UPDATE roles SET permissions = permissions || '["#{KEY}"]'::jsonb, updated_at = NOW()
      WHERE key IN ('owner', 'super_manager')
        AND NOT permissions @> '["#{KEY}"]'::jsonb
    SQL
  end

  def down
    execute "UPDATE roles SET permissions = permissions - '#{KEY}'"
  end
end
