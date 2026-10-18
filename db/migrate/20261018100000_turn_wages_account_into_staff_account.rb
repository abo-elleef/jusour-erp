class TurnWagesAccountIntoStaffAccount < ActiveRecord::Migration[7.1]
  # Self-contained on purpose (raw SQL, no app models) — see
  # feedback_migrations_no_app_models.
  #
  # Each employee's account stops being an expense and becomes a current
  # account on the balance sheet: the month's earnings are credited to it when
  # payroll is finalized, and every voucher paid to (or received from) the
  # employee moves it. So it leaves the 6000 expense block for a liability
  # code, 2500 + ordinal, clear of tax payable (2100), loans (2101+),
  # equipment payable (2200) and accrued expenses (2300). Nothing has posted
  # to the 6000 codes yet, so renumbering touches no ledger lines.
  #
  # payroll_snapshots.payout_voucher_id — the voucher that paid the balance
  # out when the month was finalized, so undoing the month can void it.
  #
  # payroll_advances.converted_voucher_id — which voucher an advance became
  # when payroll:convert_to_staff_accounts rewrote it. Audit trail and the
  # task's idempotency key; the table goes once production has baked.
  def up
    execute <<~SQL.squish
      WITH ordered AS (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY company_id ORDER BY name, id) AS ordinal
        FROM users
      )
      UPDATE users SET wages_account_code = 2500 + ordered.ordinal
      FROM ordered WHERE users.id = ordered.id
    SQL

    add_reference :payroll_snapshots, :payout_voucher, type: :uuid, foreign_key: { to_table: :vouchers }, null: true
    add_reference :payroll_advances, :converted_voucher, type: :uuid, foreign_key: { to_table: :vouchers }, null: true
  end

  def down
    remove_reference :payroll_advances, :converted_voucher, foreign_key: { to_table: :vouchers }
    remove_reference :payroll_snapshots, :payout_voucher, foreign_key: { to_table: :vouchers }

    execute <<~SQL.squish
      WITH ordered AS (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY company_id ORDER BY name, id) AS ordinal
        FROM users
      )
      UPDATE users SET wages_account_code = 6000 + ordered.ordinal
      FROM ordered WHERE users.id = ordered.id
    SQL
  end
end
