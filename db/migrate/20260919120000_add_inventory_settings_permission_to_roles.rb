# frozen_string_literal: true

class AddInventorySettingsPermissionToRoles < ActiveRecord::Migration[7.1]
  # Writing to the inventory catalog — ingredients, vendors, categories, units —
  # moves off inventory:manage onto its own key, so a role can run stock
  # (transfers, takes, adjustments, invoices) without reshaping what the stock
  # is made of.
  #
  # Nobody loses anything here: every role that could already edit the catalog
  # (i.e. holds inventory:manage) keeps it. Owners narrow it from the role
  # editor afterwards, which is the point of splitting it out.
  def up
    execute(<<~SQL)
      UPDATE roles
      SET permissions = permissions || '["inventory:settings"]'::jsonb
      WHERE permissions @> '["inventory:manage"]'::jsonb
        AND NOT (permissions @> '["inventory:settings"]'::jsonb)
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE roles
      SET permissions = (
        SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
        FROM jsonb_array_elements_text(permissions) AS elem
        WHERE elem <> 'inventory:settings'
      )
    SQL
  end
end
