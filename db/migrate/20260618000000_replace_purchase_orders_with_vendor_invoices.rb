# frozen_string_literal: true

class ReplacePurchaseOrdersWithVendorInvoices < ActiveRecord::Migration[7.1]
  def up
    create_table :vendor_invoices, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :supplier, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :invoice_number, null: false
      t.date :invoice_date, null: false
      t.date :received_on, null: false
      t.string :payment_status, null: false, default: "unpaid"
      t.integer :total_cents, null: false, default: 0
      t.text :notes
      t.datetime :paid_at
      t.references :paid_by_user, type: :uuid, foreign_key: { to_table: :users }
      t.references :treasury, type: :uuid, foreign_key: true
      t.timestamps
    end

    add_index :vendor_invoices, %i[company_id supplier_id invoice_number],
      unique: true, name: "index_vendor_invoices_on_company_supplier_and_number"
    add_index :vendor_invoices, :payment_status
    add_index :vendor_invoices, :invoice_date

    create_table :vendor_invoice_lines, id: :uuid do |t|
      t.references :vendor_invoice, type: :uuid, null: false, foreign_key: true
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 3, null: false
      t.integer :unit_price_cents, null: false
      t.date :expires_on
      t.string :batch_reference
      t.text :line_notes
      t.timestamps
    end

    add_reference :stock_batches, :vendor_invoice_line, type: :uuid, foreign_key: true, null: true

    drop_table :purchase_order_items
    drop_table :purchase_orders

    Company.find_each do |company|
      ExpenseCategory.find_or_create_by!(name: "Vendor purchases", company: company) do |category|
        category.category_type = "other"
        category.system_managed = true
        category.position = 0
      end
    end
  end

  def down
    remove_reference :stock_batches, :vendor_invoice_line, type: :uuid, foreign_key: true

    drop_table :vendor_invoice_lines
    drop_table :vendor_invoices

    create_table :purchase_orders, id: :uuid do |t|
      t.uuid :supplier_id, null: false
      t.uuid :user_id, null: false
      t.string :po_number, null: false
      t.string :status, default: "draft", null: false
      t.date :ordered_on
      t.date :expected_on
      t.integer :total_cents, default: 0
      t.text :notes
      t.timestamps
      t.uuid :company_id, null: false
    end

    create_table :purchase_order_items, id: :uuid do |t|
      t.uuid :purchase_order_id, null: false
      t.uuid :ingredient_id, null: false
      t.decimal :quantity_ordered, precision: 10, scale: 3, null: false
      t.decimal :quantity_received, precision: 10, scale: 3, default: "0.0"
      t.integer :unit_price_cents, null: false
      t.string :status, default: "pending"
      t.text :discrepancy_notes
      t.timestamps
    end
  end
end
