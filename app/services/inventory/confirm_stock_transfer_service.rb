# frozen_string_literal: true

module Inventory
  class ConfirmStockTransferService
    class InsufficientStockError < StandardError; end

    def initialize(transfer, user, line_quantities:)
      @transfer = transfer
      @user = user
      @line_quantities = line_quantities.transform_keys(&:to_s)
    end

    def call
      raise ActiveRecord::RecordInvalid, @transfer unless @transfer.sent?

      ActiveRecord::Base.transaction do
        @transfer.stock_transfer_lines.each do |line|
          qty = received_quantity_for(line)
          line.update!(quantity_received: qty)
          move_stock!(line, qty) if qty.positive?
        end

        @transfer.update!(
          status: "received",
          received_at: Time.current,
          received_by: @user
        )
      end

      @transfer
    end

    private

    def received_quantity_for(line)
      raw = @line_quantities[line.id.to_s]
      qty = raw.present? ? raw.to_d : line.quantity_sent.to_d
      raise ActiveRecord::RecordInvalid, line if qty.negative?

      qty
    end

    def move_stock!(line, quantity)
      cost_per_unit_cents = deduct_from_location!(line.ingredient, @transfer.from_location, quantity)
      add_to_location!(line.ingredient, @transfer.to_location, quantity, cost_per_unit_cents)
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
        reason_notes: transfer_note("out", location)
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
        batch_reference: "XFER-#{@transfer.transfer_number}"
      )

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @user,
        location: location,
        stock_batch: batch,
        stock_transfer: @transfer,
        quantity_delta: quantity,
        adjustment_type: "transfer_in",
        reason_notes: transfer_note("in", location)
      )
    end

    def ensure_ingredient_at_location!(ingredient, location)
      location.ingredient_locations.find_or_create_by!(ingredient: ingredient) do |il|
        il.reorder_threshold = ingredient.reorder_threshold
        il.quantity_on_hand = 0
      end
    end

    def transfer_note(direction, location)
      I18n.t("inventory.stock_transfers.adjustment.#{direction}",
        number: @transfer.transfer_number,
        from: @transfer.from_location.name,
        to: @transfer.to_location.name,
        location: location.name)
    end
  end
end
