# frozen_string_literal: true

# A drawer shortage is charged to the drawer's cashier at close (a payment
# voucher to their staff account). Reviewing the day afterwards, the accountant
# may find someone else handled that cash and move the charge to them, with a
# reason. The drawer remembers who carries it now (shortage_charged_to_id) so a
# re-sync (waive, un-waive, count correction) keeps it there; each move is kept
# as its own row for the "shortage moves" report.
#
# New permission accounting:reassign_shortage, granted to the owner, super
# manager and accountant built-in roles. Raw SQL on purpose (no app models in
# migrations); Roles::Seeder never backfills new keys into existing roles.
class CreateDrawerShortageReassignments < ActiveRecord::Migration[7.1]
  KEY = "accounting:reassign_shortage"

  def up
    add_reference :cash_drawer_sessions, :shortage_charged_to, type: :uuid,
                  foreign_key: { to_table: :users }, index: true

    create_table :drawer_shortage_reassignments, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :cash_drawer_session, type: :uuid, null: false, foreign_key: true
      t.references :from_user, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.references :to_user, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.references :reassigned_by, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.references :old_voucher, type: :uuid, foreign_key: { to_table: :vouchers }
      t.references :new_voucher, type: :uuid, foreign_key: { to_table: :vouchers }
      t.integer :amount_cents, null: false
      t.text :reason, null: false
      t.timestamps
    end
    add_index :drawer_shortage_reassignments, %i[company_id created_at]

    execute <<~SQL.squish
      UPDATE roles SET permissions = permissions || '["#{KEY}"]'::jsonb, updated_at = NOW()
      WHERE key IN ('owner', 'super_manager', 'accountant')
        AND NOT permissions @> '["#{KEY}"]'::jsonb
    SQL
  end

  def down
    execute "UPDATE roles SET permissions = permissions - '#{KEY}'"
    drop_table :drawer_shortage_reassignments
    remove_reference :cash_drawer_sessions, :shortage_charged_to, foreign_key: { to_table: :users }
  end
end
