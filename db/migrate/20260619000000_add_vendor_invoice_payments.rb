# frozen_string_literal: true

class AddVendorInvoicePayments < ActiveRecord::Migration[7.1]
  class MigrationVendorInvoice < ApplicationRecord
    self.table_name = "vendor_invoices"
  end

  class MigrationVendorInvoicePayment < ApplicationRecord
    self.table_name = "vendor_invoice_payments"
  end

  class MigrationExpense < ApplicationRecord
    self.table_name = "expenses"
  end

  def up
    add_column :vendor_invoices, :amount_paid_cents, :integer, null: false, default: 0

    create_table :vendor_invoice_payments, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :vendor_invoice, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :treasury, type: :uuid, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.date :payment_date, null: false
      t.timestamps
    end

    add_index :vendor_invoice_payments, :payment_date

    MigrationVendorInvoice.reset_column_information

    MigrationVendorInvoice.where(payment_status: "paid").find_each do |invoice|
      expense = MigrationExpense.find_by(source_record_type: "VendorInvoice", source_record_id: invoice.id)
      amount_cents = expense&.amount_cents || invoice.total_cents

      if expense
        payment = MigrationVendorInvoicePayment.create!(
          company_id: invoice.company_id,
          vendor_invoice_id: invoice.id,
          user_id: expense.user_id,
          treasury_id: expense.treasury_id,
          amount_cents: amount_cents,
          payment_date: expense.expense_date,
          created_at: expense.created_at,
          updated_at: expense.updated_at
        )
        expense.update_columns(source_record_type: "VendorInvoicePayment", source_record_id: payment.id)
      end

      invoice.update_columns(amount_paid_cents: amount_cents)
    end

    remove_reference :vendor_invoices, :paid_by_user, type: :uuid, foreign_key: { to_table: :users }
    remove_reference :vendor_invoices, :treasury, type: :uuid, foreign_key: true
    remove_column :vendor_invoices, :paid_at, :datetime
  end

  def down
    add_column :vendor_invoices, :paid_at, :datetime
    add_reference :vendor_invoices, :paid_by_user, type: :uuid, foreign_key: { to_table: :users }
    add_reference :vendor_invoices, :treasury, type: :uuid, foreign_key: true

    drop_table :vendor_invoice_payments
    remove_column :vendor_invoices, :amount_paid_cents
  end
end
