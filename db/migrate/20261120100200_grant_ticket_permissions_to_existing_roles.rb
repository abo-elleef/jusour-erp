# frozen_string_literal: true

# New permissions tickets:manage and tickets:assign (Bazzar slice G1). Every
# role that manages customers or sees the whole sales area today gets both, so
# existing managers can work tickets from day one; the owner then trims them
# per role. Raw SQL on purpose (no app models in migrations); Roles::Seeder
# never backfills new keys into roles a company already has.
class GrantTicketPermissionsToExistingRoles < ActiveRecord::Migration[7.1]
  KEYS = %w[tickets:manage tickets:assign].freeze

  def up
    KEYS.each do |key|
      execute <<~SQL.squish
        UPDATE roles SET permissions = permissions || '["#{key}"]'::jsonb, updated_at = NOW()
        WHERE permissions ?| ARRAY['customers:manage', 'sales:see_all']
          AND NOT permissions @> '["#{key}"]'::jsonb
      SQL
    end
  end

  def down
    KEYS.each { |key| execute "UPDATE roles SET permissions = permissions - '#{key}'" }
  end
end
