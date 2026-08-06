# frozen_string_literal: true

class AddCompanyIdToCashDrawerSessions < ActiveRecord::Migration[7.1]
  def up
    add_column :cash_drawer_sessions, :company_id, :uuid
    execute <<~SQL
      UPDATE cash_drawer_sessions
         SET company_id = users.company_id
        FROM users
       WHERE users.id = cash_drawer_sessions.user_id
    SQL
    # Orphan sessions (deleted user) — attach via location when possible.
    execute <<~SQL
      UPDATE cash_drawer_sessions
         SET company_id = locations.company_id
        FROM locations
       WHERE locations.id = cash_drawer_sessions.location_id
         AND cash_drawer_sessions.company_id IS NULL
    SQL
    execute <<~SQL
      UPDATE cash_drawer_sessions
         SET company_id = treasuries.company_id
        FROM treasuries
       WHERE treasuries.id = cash_drawer_sessions.treasury_id
         AND cash_drawer_sessions.company_id IS NULL
    SQL

    # Drop any remaining orphans rather than leave nullable rows.
    execute "DELETE FROM cash_drawer_sessions WHERE company_id IS NULL"

    change_column_null :cash_drawer_sessions, :company_id, false
    add_index :cash_drawer_sessions, :company_id
    add_foreign_key :cash_drawer_sessions, :companies
  end

  def down
    remove_foreign_key :cash_drawer_sessions, :companies
    remove_index :cash_drawer_sessions, :company_id
    remove_column :cash_drawer_sessions, :company_id
  end
end
