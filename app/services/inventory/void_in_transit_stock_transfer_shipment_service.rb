# frozen_string_literal: true

module Inventory
  # Voids the current in-transit shipment without moving stock (send never deducts inventory).
  # Rolls back line quantity_sent totals and restores the transfer to requested or partially_received.
  class VoidInTransitStockTransferShipmentService
    # Explicit shipment: several may be open at once.
    def initialize(transfer, user, shipment: nil)
      @transfer = transfer
      @user = user
      @shipment = shipment || transfer.current_shipment
    end

    def call
      unless @shipment.present? && @shipment.in_transit? &&
             @shipment.stock_transfer_id == @transfer.id
        @transfer.errors.add(:status, I18n.t("inventory.stock_transfers.errors.cannot_void_shipment"))
        raise ActiveRecord::RecordInvalid, @transfer
      end

      ActiveRecord::Base.transaction do
        @shipment.stock_transfer_shipment_lines.includes(:stock_transfer_line).find_each do |shipment_line|
          line = shipment_line.stock_transfer_line
          line.update!(quantity_sent: line.quantity_sent.to_d - shipment_line.quantity_sent.to_d)
        end

        @shipment.update!(
          status: "voided",
          voided_at: Time.current,
          voided_by: @user
        )

        sync_transfer_after_void!
      end

      @transfer
    end

    private

    def sync_transfer_after_void!
      active_shipments = @transfer.stock_transfer_shipments.where(status: %w[in_transit received]).ordered
      latest_sent = active_shipments.last
      latest_received = @transfer.stock_transfer_shipments.received.order(:sequence).last

      @transfer.update!(
        status: @transfer.recalculated_status,
        sent_at: latest_sent&.sent_at,
        sent_by: latest_sent&.sent_by,
        received_at: latest_received&.received_at,
        received_by: latest_received&.received_by
      )
    end
  end
end
