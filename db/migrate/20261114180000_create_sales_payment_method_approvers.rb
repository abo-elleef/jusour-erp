# frozen_string_literal: true

# Who approves payments made by a given online method (e.g. the holder of the
# "Vodafone Cash — Saif" wallet). Many-to-many: a method can have several
# approvers and one person can approve several methods. A method with no
# approvers keeps today's rule: anyone with sales:confirm_payments.
class CreateSalesPaymentMethodApprovers < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_payment_method_approvers, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :sales_payment_method, null: false, foreign_key: true, type: :uuid,
        index: { name: "index_sales_pm_approvers_on_payment_method_id" }
      t.references :user, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :sales_payment_method_approvers, %i[sales_payment_method_id user_id], unique: true,
      name: "index_sales_pm_approvers_on_method_and_user"
  end
end
