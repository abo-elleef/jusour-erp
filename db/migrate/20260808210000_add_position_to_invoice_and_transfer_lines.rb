# frozen_string_literal: true

class AddPositionToInvoiceAndTransferLines < ActiveRecord::Migration[7.1]
  def up
    add_column :vendor_invoice_lines, :position, :integer, null: false, default: 0
    add_column :stock_transfer_lines, :position, :integer, null: false, default: 0

    backfill_positions(:vendor_invoice_lines, :vendor_invoice_id)
    backfill_positions(:stock_transfer_lines, :stock_transfer_id)
  end

  def down
    remove_column :vendor_invoice_lines, :position
    remove_column :stock_transfer_lines, :position
  end

  private

  def backfill_positions(table, parent_id)
    say_with_time "Backfill #{table}.position" do
      execute <<~SQL.squish
        UPDATE #{table} AS lines
        SET position = ranked.rn - 1
        FROM (
          SELECT id, ROW_NUMBER() OVER (
            PARTITION BY #{parent_id} ORDER BY created_at ASC, id ASC
          ) AS rn
          FROM #{table}
        ) AS ranked
        WHERE lines.id = ranked.id
      SQL
    end
  end
end
