# frozen_string_literal: true

module Sales
  # Links a payment method to a user who approves payments made by it.
  class PaymentMethodApprover < ApplicationRecord
    self.table_name = "sales_payment_method_approvers"

    include Tenantable

    belongs_to :sales_payment_method, class_name: "Sales::PaymentMethod"
    belongs_to :user

    validates :user_id, uniqueness: { scope: :sales_payment_method_id }
  end
end
