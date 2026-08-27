# frozen_string_literal: true

# Who actually made the sale (for their bonus) — distinct from user_id, who
# recorded it in the system. Defaults to the recorder but is changeable.
class AddSalespersonToCustomerInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :customer_invoices, :salesperson_id, :uuid
    add_index :customer_invoices, :salesperson_id
  end
end
