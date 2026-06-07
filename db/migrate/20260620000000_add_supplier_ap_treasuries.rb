# frozen_string_literal: true

class AddSupplierApTreasuries < ActiveRecord::Migration[7.1]
  # Lightweight local references so we don't rely on app models during migration
  class MigrationSupplier < ApplicationRecord
    self.table_name = "suppliers"
  end

  class MigrationTreasury < ApplicationRecord
    self.table_name = "treasuries"
  end

  class MigrationVendorInvoice < ApplicationRecord
    self.table_name = "vendor_invoices"
  end

  def up
    # Link treasuries back to their supplier (for supplier_ap type)
    add_column :treasuries, :supplier_id, :uuid, null: true
    add_index  :treasuries, :supplier_id

    # Link each supplier to its AP treasury
    add_reference :suppliers, :treasury, type: :uuid, null: true, foreign_key: true

    MigrationSupplier.reset_column_information
    MigrationTreasury.reset_column_information

    # Backfill: create one AP treasury per existing supplier
    MigrationSupplier.all.find_each do |supplier|
      outstanding_cents = MigrationVendorInvoice
        .where(supplier_id: supplier.id, payment_status: %w[unpaid partially_paid])
        .sum(Arel.sql("total_cents - amount_paid_cents"))

      base_name = "#{supplier.name} — AP"
      name = if MigrationTreasury.exists?(name: base_name, company_id: supplier.company_id)
               "#{supplier.name} — AP (#{supplier.id[0, 6]})"
             else
               base_name
             end

      treasury = MigrationTreasury.create!(
        name: name,
        treasury_type: "supplier_ap",
        balance_cents: outstanding_cents,
        opening_balance_cents: outstanding_cents,
        active: true,
        is_default: false,
        position: 9999,
        company_id: supplier.company_id,
        supplier_id: supplier.id,
        created_at: Time.current,
        updated_at: Time.current
      )

      supplier.update_columns(treasury_id: treasury.id)
    end
  end

  def down
    # Remove supplier_id from treasuries
    remove_index  :treasuries, :supplier_id, if_exists: true
    remove_column :treasuries, :supplier_id

    # Remove treasury_id from suppliers
    remove_reference :suppliers, :treasury, foreign_key: true
  end
end
