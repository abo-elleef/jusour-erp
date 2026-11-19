# frozen_string_literal: true

# A method with this ticked refuses to confirm (or submit for approval) an
# invoice until its payment-proof image is attached. Off for existing methods.
class AddRequiresProofImageToSalesPaymentMethods < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_payment_methods, :requires_proof_image, :boolean, default: false, null: false
  end
end
