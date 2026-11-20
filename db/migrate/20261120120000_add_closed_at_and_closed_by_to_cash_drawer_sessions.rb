# frozen_string_literal: true

# A drawer's close used to be known only from its updated_at (which a later count
# correction moves) and its "cash_drawer.reconciled" audit entry (which names the
# drawer's cashier, never the person who closed it).
#
# Backfill, raw SQL only:
# - closed_at: the first "cash_drawer.reconciled" entry after the drawer's last
#   reopen, so a count correction does not move it; updated_at when no entry exists.
# - closed_by_id: the user on that entry. Old entries always named the drawer's
#   cashier, so a drawer a manager closed from admin is backfilled with the cashier;
#   nothing older records who really closed it.
class AddClosedAtAndClosedByToCashDrawerSessions < ActiveRecord::Migration[7.1]
  def up
    add_column :cash_drawer_sessions, :closed_at, :datetime
    add_reference :cash_drawer_sessions, :closed_by, type: :uuid, foreign_key: { to_table: :users }, index: true

    execute <<~SQL
      WITH last_reopen AS (
        SELECT record_id, MAX(created_at) AS at
        FROM audit_log_entries
        WHERE record_type = 'CashDrawerSession' AND action = 'cash_drawer.reopened'
        GROUP BY record_id
      ),
      first_close AS (
        SELECT DISTINCT ON (e.record_id) e.record_id, e.created_at, e.user_id
        FROM audit_log_entries e
        LEFT JOIN last_reopen r ON r.record_id = e.record_id
        WHERE e.record_type = 'CashDrawerSession'
          AND e.action = 'cash_drawer.reconciled'
          AND (r.at IS NULL OR e.created_at > r.at)
        ORDER BY e.record_id, e.created_at
      )
      UPDATE cash_drawer_sessions s
      SET closed_at = COALESCE(fc.created_at, s.updated_at),
          closed_by_id = COALESCE(fc.user_id, s.user_id)
      FROM cash_drawer_sessions s2
      LEFT JOIN first_close fc ON fc.record_id = s2.id
      WHERE s.id = s2.id AND s.status <> 'open'
    SQL
  end

  def down
    remove_reference :cash_drawer_sessions, :closed_by, foreign_key: { to_table: :users }
    remove_column :cash_drawer_sessions, :closed_at
  end
end
