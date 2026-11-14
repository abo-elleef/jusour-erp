# frozen_string_literal: true

# A transfer or wallet payment has to be checked before it counts, but a card
# machine payment is settled at the counter. Methods that don't need approval
# settle on confirm, like cash. Existing methods keep today's behaviour (true).
class AddRequiresApprovalToSalesPaymentMethods < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_payment_methods, :requires_approval, :boolean, null: false, default: true
  end
end
