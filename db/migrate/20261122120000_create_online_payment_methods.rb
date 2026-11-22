# frozen_string_literal: true

# Which payment methods a branch offers to self-ordering customers, and whether a
# method must be paid before ordering (the customer attaches a screenshot of the
# transfer). A branch with no rows offers cash only, as before.
class CreateOnlinePaymentMethods < ActiveRecord::Migration[7.1]
  def change
    create_table :online_payment_methods, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :location, type: :uuid, null: false, foreign_key: true
      t.string :payment_method, null: false
      t.boolean :enabled, null: false, default: false
      t.boolean :requires_proof, null: false, default: false
      t.text :pay_to
      t.timestamps
    end
    add_index :online_payment_methods, %i[location_id payment_method], unique: true

    # The method the customer chose and whether it was "pay before ordering" at the
    # time, so changing the branch settings later never changes a past request.
    add_column :online_order_requests, :payment_method, :string, null: false, default: "cash"
    add_column :online_order_requests, :prepaid, :boolean, null: false, default: false
  end
end
