# frozen_string_literal: true

module Inventory
  class SendStockTransferService
    def initialize(transfer, user, line_quantities:)
      @transfer = transfer
      @user = user
      @line_quantities = line_quantities.transform_keys(&:to_s)
    end

    def call
      unless @transfer.can_send?
        @transfer.errors.add(:status, I18n.t("inventory.stock_transfers.errors.cannot_send"))
        raise ActiveRecord::RecordInvalid, @transfer
      end

      ActiveRecord::Base.transaction do
        shipment_lines = build_shipment_lines
        if shipment_lines.empty?
          @transfer.errors.add(:base, I18n.t("inventory.stock_transfers.errors.shipment_empty"))
          raise ActiveRecord::RecordInvalid, @transfer
        end

        sequence = (@transfer.stock_transfer_shipments.maximum(:sequence) || 0) + 1
        occurred_at = @transfer.occurred_at
        shipment = @transfer.stock_transfer_shipments.create!(
          sequence: sequence,
          status: "in_transit",
          sent_by: @user,
          sent_at: occurred_at
        )

        shipment_lines.each do |line, qty|
          shipment.stock_transfer_shipment_lines.create!(
            stock_transfer_line: line,
            quantity_sent: qty
          )
          line.update!(quantity_sent: line.quantity_sent.to_d + qty)
        end

        @transfer.update!(
          status: "awaiting_receipt",
          sent_at: occurred_at,
          sent_by: @user
        )
      end

      @transfer
    end

    private

    def build_shipment_lines
      lines = {}

      @transfer.stock_transfer_lines.each do |line|
        qty = shipment_quantity_for(line)
        next if qty.zero?

        validate_pending_quantity!(line, qty)
        validate_source_stock!(line, qty) if Setting.restrict_stock_transfers_to_source?
        lines[line] = qty
      end

      lines
    end

    def shipment_quantity_for(line)
      raw = @line_quantities[line.id.to_s]
      qty = if raw.present?
              raw.to_d
            else
              line.quantity_pending_send
            end
      raise ActiveRecord::RecordInvalid, line if qty.negative?

      qty
    end

    def validate_pending_quantity!(line, qty)
      return if qty <= line.quantity_pending_send

      line.errors.add(:quantity_sent, I18n.t("inventory.stock_transfers.errors.exceeds_pending",
        ingredient: line.ingredient.name, pending: line.quantity_pending_send, quantity: qty))
      raise ActiveRecord::RecordInvalid, line
    end

    def validate_source_stock!(line, qty)
      available = line.transferable_quantity_at_source
      return if available >= qty

      line.errors.add(:quantity_sent, I18n.t("inventory.stock_transfers.errors.insufficient_stock",
        ingredient: line.ingredient.name, available: available, requested: qty))
      raise ActiveRecord::RecordInvalid, line
    end
  end
end
