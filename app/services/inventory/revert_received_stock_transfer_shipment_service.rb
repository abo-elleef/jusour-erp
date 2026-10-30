# frozen_string_literal: true

module Inventory
  # Undoes a shipment that was already received: moves the goods back to the
  # source and rolls the transfer's sent/received totals back, so the transfer
  # reads as though this shipment never happened.
  #
  # This is a compensating movement, not a true rewind. Receiving drew the source
  # down FIFO but recorded only the total on its transfer_out adjustment, with no
  # per-batch trace, so the original source batches cannot be restored. The stock
  # comes back as one new batch at the cost the shipment carried — the money is
  # exact, the batch ages are not.
  #
  # An in-transit shipment is voided instead; sending moves no stock, so there is
  # nothing to put back.
  class RevertReceivedStockTransferShipmentService
    class AlreadyConsumedError < StandardError; end

    Result = Struct.new(:shipment, :short_lines, keyword_init: true) do
      # Lines the destination could not fully cover because the goods had already
      # been used or moved on. The reversal still happens — otherwise a mistaken
      # receipt could never be corrected — but the destination is left negative
      # and needs a count.
      def left_destination_short?
        short_lines.any?
      end
    end

    def initialize(transfer, user, shipment:, reason:)
      @transfer = transfer
      @user = user
      @shipment = shipment
      @reason = reason.to_s.strip
    end

    def call
      validate!

      short_lines = []

      ActiveRecord::Base.transaction do
        occurred_at = Time.current

        @shipment.stock_transfer_shipment_lines.includes(stock_transfer_line: :ingredient).each do |shipment_line|
          line = shipment_line.stock_transfer_line
          received = shipment_line.quantity_received.to_d

          if received.positive?
            shortfall = move_stock_back!(line.ingredient, received, at: occurred_at)
            short_lines << { line: line, quantity: received, shortfall: shortfall } if shortfall.positive?
          end

          # Roll back both totals: a reverted shipment never left and never
          # arrived, which is what makes the sender's outstanding amount correct
          # again and lets them re-send.
          line.update!(
            quantity_sent: [line.quantity_sent.to_d - shipment_line.quantity_sent.to_d, 0].max,
            quantity_received: [line.quantity_received.to_d - received, 0].max
          )
        end

        @shipment.update!(
          status: "reverted",
          reverted_at: occurred_at,
          reverted_by: @user,
          reverted_reason: @reason
        )

        sync_transfer_after_revert!
      end

      Result.new(shipment: @shipment, short_lines: short_lines)
    end

    private

    def validate!
      unless @shipment.present? && @shipment.can_revert? &&
             @shipment.stock_transfer_id == @transfer.id
        @transfer.errors.add(:status, I18n.t("inventory.stock_transfers.errors.cannot_revert_shipment"))
        raise ActiveRecord::RecordInvalid, @transfer
      end

      return if @reason.present?

      @transfer.errors.add(:base, I18n.t("inventory.stock_transfers.errors.revert_reason_required"))
      raise ActiveRecord::RecordInvalid, @transfer
    end

    # => shortfall the destination could not cover
    def move_stock_back!(ingredient, quantity, at:)
      cost_per_unit_cents = shipment_cost_for(ingredient)
      shortfall = take_from_destination!(ingredient, quantity, cost_per_unit_cents, at: at)
      return_to_source!(ingredient, quantity, cost_per_unit_cents, at: at)
      shortfall
    end

    # The cost the goods arrived at, read off the batch this shipment created, so
    # the value going back to the source is the value that left it.
    def shipment_cost_for(ingredient)
      batch = ingredient.stock_batches.find_by(
        location: @transfer.to_location,
        batch_reference: arrival_batch_reference
      )
      batch&.cost_per_unit_cents || ingredient.cost_per_unit_cents
    end

    def arrival_batch_reference
      "XFER-#{@transfer.transfer_number}-#{@shipment.sequence}"
    end

    # Takes the goods out of the batch this shipment created first — that is
    # literally the stock being sent back — then falls back to FIFO for anything
    # it can no longer cover.
    #
    # The shortfall is measured against the destination's on-hand, not against
    # what its batches still hold. The two can drift — a consumption recorded
    # without batch maintenance moves the balance but leaves the batch alone —
    # and on-hand is both what the user sees and what actually goes negative.
    def take_from_destination!(ingredient, quantity, cost_per_unit_cents, at:)
      on_hand = IngredientLocation
        .find_by(ingredient_id: ingredient.id, location_id: @transfer.to_location_id)
        &.quantity_on_hand.to_d
      shortfall = [quantity.to_d - on_hand, 0].max

      remaining = quantity.to_d

      arrival = ingredient.stock_batches.find_by(
        location: @transfer.to_location,
        batch_reference: arrival_batch_reference
      )
      remaining -= draw_from(arrival, remaining) if arrival

      ingredient.stock_batches.where(location: @transfer.to_location).fifo_order.with_stock.each do |batch|
        break if remaining <= 0

        remaining -= draw_from(batch, remaining)
      end

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @user,
        location: @transfer.to_location,
        stock_transfer: @transfer,
        quantity_delta: -quantity,
        # The same cost return_to_source! re-creates at the source, so the
        # revert moves value back without making or losing any.
        unit_cost_cents: cost_per_unit_cents,
        adjustment_type: "transfer_out",
        reason_notes: revert_note("out", @transfer.to_location),
        created_at: at,
        updated_at: at
      )

      shortfall
    end

    def draw_from(batch, wanted)
      return 0.to_d if wanted <= 0

      take = [batch.quantity_remaining.to_d, wanted].min
      return 0.to_d unless take.positive?

      batch.update!(quantity_remaining: batch.quantity_remaining.to_d - take)
      take
    end

    def return_to_source!(ingredient, quantity, cost_per_unit_cents, at:)
      batch = StockBatch.create!(
        ingredient: ingredient,
        location: @transfer.from_location,
        quantity_received: quantity,
        quantity_remaining: quantity,
        cost_per_unit_cents: cost_per_unit_cents,
        received_on: @transfer.transferred_on,
        batch_reference: "#{arrival_batch_reference}-REV",
        created_at: at,
        updated_at: at
      )

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @user,
        location: @transfer.from_location,
        stock_batch: batch,
        stock_transfer: @transfer,
        quantity_delta: quantity,
        adjustment_type: "transfer_in",
        reason_notes: revert_note("in", @transfer.from_location),
        created_at: at,
        updated_at: at
      )
    end

    def sync_transfer_after_revert!
      active = @transfer.stock_transfer_shipments.where(status: %w[in_transit received]).ordered
      latest_sent = active.last
      latest_received = @transfer.stock_transfer_shipments.received.order(:sequence).last

      @transfer.update!(
        status: @transfer.recalculated_status,
        sent_at: latest_sent&.sent_at,
        sent_by: latest_sent&.sent_by,
        received_at: latest_received&.received_at,
        received_by: latest_received&.received_by
      )
    end

    def revert_note(direction, location)
      I18n.t("inventory.stock_transfers.adjustment.revert_#{direction}",
        number: @transfer.transfer_number,
        shipment: @shipment.sequence,
        location: location.name)
    end
  end
end
