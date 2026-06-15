# frozen_string_literal: true

class AddStockTransferShipments < ActiveRecord::Migration[7.1]
  def up
    create_table :stock_transfer_shipments, id: :uuid do |t|
      t.references :stock_transfer, null: false, foreign_key: true, type: :uuid
      t.integer :sequence, null: false, default: 1
      t.string :status, null: false, default: "in_transit"
      t.references :sent_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :received_by, foreign_key: { to_table: :users }, type: :uuid
      t.datetime :sent_at, null: false
      t.datetime :received_at
      t.timestamps
    end

    add_index :stock_transfer_shipments, %i[stock_transfer_id sequence], unique: true

    create_table :stock_transfer_shipment_lines, id: :uuid do |t|
      t.references :stock_transfer_shipment, null: false, foreign_key: true, type: :uuid
      t.references :stock_transfer_line, null: false, foreign_key: true, type: :uuid
      t.decimal :quantity_sent, null: false, precision: 10, scale: 3, default: "0.0"
      t.decimal :quantity_received, precision: 10, scale: 3
      t.timestamps
    end

    add_index :stock_transfer_shipment_lines,
              %i[stock_transfer_shipment_id stock_transfer_line_id],
              unique: true,
              name: "index_shipment_lines_on_shipment_and_transfer_line"

    change_column_default :stock_transfer_lines, :quantity_sent, from: nil, to: 0
    change_column_default :stock_transfer_lines, :quantity_received, from: nil, to: 0
    StockTransferLine.where(quantity_sent: nil).update_all(quantity_sent: 0)
    StockTransferLine.where(quantity_received: nil).update_all(quantity_received: 0)

    migrate_transfer_statuses
    backfill_shipments
  end

  def down
    StockTransfer.where(status: "awaiting_receipt").update_all(status: "sent")
    StockTransfer.where(status: %w[partially_received completed]).update_all(status: "received")

    drop_table :stock_transfer_shipment_lines
    drop_table :stock_transfer_shipments
  end

  private

  def migrate_transfer_statuses
    execute <<~SQL.squish
      UPDATE stock_transfers SET status = 'awaiting_receipt' WHERE status = 'sent';
      UPDATE stock_transfers SET status = 'completed' WHERE status = 'received';
    SQL
  end

  def backfill_shipments
    StockTransfer.reset_column_information

    StockTransfer.where(status: "awaiting_receipt").find_each do |transfer|
      next if transfer.stock_transfer_shipments.exists?

      shipment = transfer.stock_transfer_shipments.create!(
        sequence: 1,
        status: "in_transit",
        sent_by_id: transfer.sent_by_id || transfer.requested_by_id,
        sent_at: transfer.sent_at || transfer.updated_at
      )

      transfer.stock_transfer_lines.each do |line|
        qty = line.quantity_sent.to_d
        next if qty.zero?

        shipment.stock_transfer_shipment_lines.create!(
          stock_transfer_line: line,
          quantity_sent: qty
        )
      end
    end

    StockTransfer.where(status: "completed").find_each do |transfer|
      next if transfer.stock_transfer_shipments.exists?

      shipment = transfer.stock_transfer_shipments.create!(
        sequence: 1,
        status: "received",
        sent_by_id: transfer.sent_by_id || transfer.requested_by_id,
        sent_at: transfer.sent_at || transfer.updated_at,
        received_by_id: transfer.received_by_id || transfer.requested_by_id,
        received_at: transfer.received_at || transfer.updated_at
      )

      transfer.stock_transfer_lines.each do |line|
        sent = line.quantity_sent.to_d
        received = line.quantity_received.to_d
        next if sent.zero? && received.zero?

        shipment.stock_transfer_shipment_lines.create!(
          stock_transfer_line: line,
          quantity_sent: sent,
          quantity_received: received
        )
      end
    end
  end
end
