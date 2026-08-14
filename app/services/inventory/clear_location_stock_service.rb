# frozen_string_literal: true

module Inventory
  # Zeros every ingredient balance at one location (on-hand + FIFO batches),
  # writing a cycle-count adjustment per item that had stock so the ledger stays auditable.
  class ClearLocationStockService
    class Error < StandardError; end

    Result = Struct.new(:adjusted_count, :batch_count, keyword_init: true)

    def initialize(location:, user:, reason_notes: nil)
      @location = location
      @user = user
      @reason_notes = reason_notes.presence || default_reason
    end

    def call
      raise Error, I18n.t("inventory.clear_location_stock.errors.location_required") if @location.blank?

      adjusted = 0
      batches_cleared = 0

      ActiveRecord::Base.transaction do
        @location.ingredient_locations.includes(:ingredient).find_each do |il|
          qty = il.quantity_on_hand.to_d
          next unless qty.positive?

          StockAdjustment.create!(
            ingredient: il.ingredient,
            user: @user,
            location: @location,
            quantity_delta: -qty,
            adjustment_type: "cycle_count_correction",
            reason_notes: @reason_notes,
            maintain_batches: true
          )
          adjusted += 1
        end

        # Clear any leftover batch remnants (ledger drift vs on-hand).
        StockBatch.where(location: @location).with_stock.find_each do |batch|
          batches_cleared += 1
          batch.update!(quantity_remaining: 0)
        end
      end

      Result.new(adjusted_count: adjusted, batch_count: batches_cleared)
    end

    private

    def default_reason
      I18n.t(
        "inventory.clear_location_stock.default_reason",
        location: @location.name
      )
    end
  end
end
