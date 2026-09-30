class AddAccountCodeToTreasuries < ActiveRecord::Migration[7.1]
  # Self-contained on purpose (raw SQL, no app models) — a from-scratch
  # migrate must reproduce exactly what production already has, and a later
  # change to Treasury's own numbering logic must never rewrite this history.
  # See feedback_migrations_no_app_models.
  def up
    add_column :treasuries, :account_code, :integer

    # Freeze today's live-computed code into place: base-per-type plus this
    # treasury's 1-based ordinal among same-company-same-type siblings —
    # exactly what account_for_treasury (and, until now, Treasury#account_code)
    # already compute on every read. Split in two because supplier AP orders
    # its siblings by name alone; everything else orders by position, then name.
    execute <<~SQL.squish
      WITH ordered AS (
        SELECT id,
               CASE treasury_type
                 WHEN 'cash_drawer'   THEN 1000
                 WHEN 'bank'          THEN 1100
                 WHEN 'customer_ar'   THEN 1150
                 WHEN 'safe'          THEN 1200
                 WHEN 'petty_cash'    THEN 1300
                 WHEN 'mobile_wallet' THEN 1400
                 ELSE 1500
               END AS base,
               ROW_NUMBER() OVER (
                 PARTITION BY company_id, treasury_type ORDER BY position, name
               ) AS ordinal
        FROM treasuries
        WHERE treasury_type <> 'supplier_ap'
      )
      UPDATE treasuries SET account_code = ordered.base + ordered.ordinal
      FROM ordered WHERE treasuries.id = ordered.id
    SQL

    execute <<~SQL.squish
      WITH ordered AS (
        SELECT id, 2000 AS base,
               ROW_NUMBER() OVER (PARTITION BY company_id ORDER BY name) AS ordinal
        FROM treasuries
        WHERE treasury_type = 'supplier_ap'
      )
      UPDATE treasuries SET account_code = ordered.base + ordered.ordinal
      FROM ordered WHERE treasuries.id = ordered.id
    SQL

    change_column_null :treasuries, :account_code, false
    add_index :treasuries, %i[company_id account_code], unique: true
  end

  def down
    remove_index :treasuries, %i[company_id account_code]
    remove_column :treasuries, :account_code
  end
end
