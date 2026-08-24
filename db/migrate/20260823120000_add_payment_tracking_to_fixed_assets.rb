# frozen_string_literal: true

# Fixed assets were a standalone register: no treasury, no journal entry, no link
# to how the machine was paid for. Recording a purchase moved no cash, so the only
# way to reduce the safe was a separate Expense — which books a capital purchase as
# an operating expense and makes it appear twice in the cash flow (once as investing
# from the register, once as operating from the Expense).
#
# The purchase becomes the accounting event instead: paid from a treasury now, or
# taken on credit and settled through installments.
class AddPaymentTrackingToFixedAssets < ActiveRecord::Migration[7.1]
  def change
    # Nil when bought on credit — the payments carry the treasuries in that case.
    add_reference :fixed_assets, :paid_from_treasury, type: :uuid, null: true,
      foreign_key: { to_table: :treasuries, on_delete: :restrict }
    add_column :fixed_assets, :on_credit, :boolean, default: false, null: false
    add_column :fixed_assets, :supplier_name, :string

    create_table :fixed_asset_payments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :fixed_asset, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :treasury, type: :uuid, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.date :payment_date, null: false
      t.text :notes
      t.timestamps
    end
    add_index :fixed_asset_payments, :payment_date
  end
end
