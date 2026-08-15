# frozen_string_literal: true

module Inventory
  class ConfirmStockTransferService
    class InsufficientStockError < StandardError; end

    def initialize(transfer, user, line_quantities:)
      @transfer = transfer
      @user = user
      @line_quantities = line_quantities.transform_keys(&:to_s)
      @shipment = transfer.current_shipment
    end

    def call
      unless @transfer.can_confirm_receipt?
        @transfer.errors.add(:status, I18n.t("inventory.stock_transfers.errors.cannot_confirm"))
        raise ActiveRecord::RecordInvalid, @transfer
      end

      ActiveRecord::Base.transaction do
        @shipment.stock_transfer_shipment_lines.each do |shipment_line|
          qty = received_quantity_for(shipment_line)
          shipment_line.update!(quantity_received: qty)
          transfer_line = shipment_line.stock_transfer_line
          transfer_line.update!(quantity_received: transfer_line.quantity_received.to_d + qty)
          move_stock!(transfer_line.ingredient, qty) if qty.positive?
        end

        @shipment.update!(
          status: "received",
          received_at: Time.current,
          received_by: @user
        )

        @transfer.update!(
          status: @transfer.fully_fulfilled? ? "completed" : "partially_received",
          received_at: Time.current,
          received_by: @user
        )
      end

      @transfer
    end

    private

    def received_quantity_for(shipment_line)
      line = shipment_line.stock_transfer_line
      raw = @line_quantities[line.id.to_s]
      qty = raw.present? ? raw.to_d : shipment_line.quantity_sent.to_d
      raise ActiveRecord::RecordInvalid, shipment_line if qty.negative?
      return qty if qty <= shipment_line.quantity_sent.to_d

      shipment_line.errors.add(:quantity_received, I18n.t("inventory.stock_transfers.errors.exceeds_shipment",
        ingredient: line.ingredient.name, sent: shipment_line.quantity_sent, quantity: qty))
      raise ActiveRecord::RecordInvalid, shipment_line
    end

    def move_stock!(ingredient, quantity)
      cost_per_unit_cents = deduct_from_location!(ingredient, @transfer.from_location, quantity)
      add_to_location!(ingredient, @transfer.to_location, quantity, cost_per_unit_cents)
    end

    def deduct_from_location!(ingredient, location, quantity)
      remaining = quantity.to_d
      total_cost_cents = 0

      ingredient.stock_batches.where(location: location).fifo_order.with_stock.each do |batch|
        break if remaining <= 0

        deductable = [batch.quantity_remaining.to_d, remaining].min
        batch.update!(quantity_remaining: batch.quantity_remaining.to_d - deductable)
        total_cost_cents += (deductable * batch.cost_per_unit_cents).round
        remaining -= deductable
      end

      if remaining.positive?
        unless Setting.restrict_stock_transfers_to_source?
          total_cost_cents += (remaining * ingredient.cost_per_unit_cents).round
          remaining = 0
        end
      end

      if remaining.positive?
        raise InsufficientStockError,
          I18n.t("inventory.stock_transfers.errors.insufficient_stock_at_send",
            ingredient: ingredient.name, quantity: quantity, available: quantity - remaining)
      end

      avg_cost = quantity.zero? ? ingredient.cost_per_unit_cents : (total_cost_cents / quantity).round

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @user,
        location: location,
        stock_transfer: @transfer,
        quantity_delta: -quantity,
        adjustment_type: "transfer_out",
        reason_notes: transfer_note("out", location, @shipment.sequence)
      )

      avg_cost
    end

    def add_to_location!(ingredient, location, quantity, cost_per_unit_cents)
      ensure_ingredient_at_location!(ingredient, location)

      batch = StockBatch.create!(
        ingredient: ingredient,
        location: location,
        quantity_received: quantity,
        quantity_remaining: quantity,
        cost_per_unit_cents: cost_per_unit_cents,
        received_on: Date.current,
        batch_reference: "XFER-#{@transfer.transfer_number}-#{@shipment.sequence}"
      )

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @user,
        location: location,
        stock_batch: batch,
        stock_transfer: @transfer,
        quantity_delta: quantity,
        adjustment_type: "transfer_in",
        reason_notes: transfer_note("in", location, @shipment.sequence)
      )
    end

    def ensure_ingredient_at_location!(ingredient, location)
      location.ingredient_locations.find_or_create_by!(ingredient: ingredient) do |il|
        il.reorder_threshold = ingredient.reorder_threshold
        il.max_quantity = ingredient.max_quantity
        il.quantity_on_hand = 0
      end
    end

    def transfer_note(direction, location, sequence)
      I18n.t("inventory.stock_transfers.adjustment.#{direction}",
        number: @transfer.transfer_number,
        shipment: sequence,
        from: @transfer.from_location.name,
        to: @transfer.to_location.name,
        location: location.name)
    end
  end
end
