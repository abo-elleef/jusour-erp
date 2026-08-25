# frozen_string_literal: true

# SPIKE: Accounts-Receivable ledger, mirroring the supplier-AP treasury pattern.
# A per-customer "customer_ar" treasury whose balance is the amount the customer
# owes us. Linked both ways, exactly like suppliers <-> AP treasuries.
class AddCustomerArLedger < ActiveRecord::Migration[7.1]
  def change
    add_reference :treasuries, :customer, type: :uuid, null: true, index: true
    add_column :customers, :treasury_id, :uuid
    add_index :customers, :treasury_id
  end
end
