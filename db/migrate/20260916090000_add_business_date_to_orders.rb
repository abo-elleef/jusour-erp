# frozen_string_literal: true

# Order numbers restart at 1 for each branch on each business day, so the number
# alone no longer identifies an order — the branch and the day it belongs to do.
#
# The business day is stored rather than derived because it cannot be computed in
# SQL: it depends on a start-hour setting that each branch may override, and on
# manual branches it comes from an open operating-day row. A unique index needs a
# column it can actually read.
#
# Orders written before this migration keep NULL here and keep their old
# company-wide numbers, so nothing already printed on a receipt is rewritten. Two
# partial unique indexes let the two schemes live side by side: the legacy one
# guards the rows with no business date, the new one guards the rest.
class AddBusinessDateToOrders < ActiveRecord::Migration[7.1]
  LEGACY_INDEX = "index_orders_on_company_id_and_order_number"
  DAILY_INDEX  = "index_orders_on_branch_day_order_number"
  NO_LOCATION  = "00000000-0000-0000-0000-000000000000"

  def up
    add_column :orders, :business_date, :date

    remove_index :orders, name: LEGACY_INDEX
    execute <<~SQL
      CREATE UNIQUE INDEX #{LEGACY_INDEX}
        ON orders (company_id, order_number)
        WHERE business_date IS NULL
    SQL

    # COALESCE, not a plain column list: Postgres treats NULLs as distinct in a
    # unique index, so two orders rung before a branch was picked would both be
    # allowed to take number 1.
    execute <<~SQL
      CREATE UNIQUE INDEX #{DAILY_INDEX}
        ON orders (company_id, COALESCE(location_id, '#{NO_LOCATION}'::uuid), business_date, order_number)
        WHERE business_date IS NOT NULL
    SQL

    add_index :orders, %i[company_id business_date], name: "index_orders_on_company_id_and_business_date"
  end

  def down
    remove_index :orders, name: "index_orders_on_company_id_and_business_date"
    execute "DROP INDEX IF EXISTS #{DAILY_INDEX}"
    execute "DROP INDEX IF EXISTS #{LEGACY_INDEX}"
    remove_column :orders, :business_date
    add_index :orders, %i[company_id order_number], name: LEGACY_INDEX, unique: true
  end
end
