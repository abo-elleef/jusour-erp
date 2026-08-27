# frozen_string_literal: true

# Step 4: landed cost. An import shipment groups goods (vendor invoices) with the
# customs/freight/clearance bills that arrive over time; finalizing allocates the
# pooled costs across the shipment's stock batches to set each product's true
# landed cost. Cost lines are cash-out Expenses; the allocation only adjusts batch
# cost (costing/pricing), never double-posting to the ledger.
class CreateImportShipments < ActiveRecord::Migration[7.1]
  def change
    create_table :import_shipments, id: :uuid do |t|
      t.references :company,  type: :uuid, null: false, index: true
      t.references :user,     type: :uuid, null: false, index: true
      t.references :location, type: :uuid, null: true, index: true
      t.string   :shipment_number, null: false
      t.string   :status, default: "open", null: false
      t.date     :arrival_date
      t.datetime :finalized_at
      t.text     :notes
      t.timestamps
    end
    add_index :import_shipments, %i[company_id shipment_number], unique: true

    create_table :shipment_costs, id: :uuid do |t|
      t.references :import_shipment, type: :uuid, null: false, index: true
      t.references :user,     type: :uuid, null: false, index: true
      t.references :treasury, type: :uuid, null: true, index: true
      t.references :expense,  type: :uuid, null: true, index: true
      t.string  :cost_type, null: false
      t.bigint  :amount_cents, null: false
      t.date    :incurred_on, null: false
      t.text    :description
      t.timestamps
    end

    add_reference :vendor_invoices, :import_shipment, type: :uuid, null: true, index: true
    # Baseline (supplier price) captured on first finalize so re-finalizing after
    # more costs arrive recomputes from scratch instead of compounding.
    add_column :stock_batches, :provisional_cost_per_unit_cents, :bigint
  end
end
