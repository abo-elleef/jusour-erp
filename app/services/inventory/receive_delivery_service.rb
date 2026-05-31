# frozen_string_literal: true

module Inventory
  class ReceiveDeliveryService
    def initialize(purchase_order, delivery_params, user)
      @po = purchase_order
      @delivery_params = delivery_params
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        @delivery_params.each do |dp|
          receive_line(dp)
        end
        update_po_status
      end
    end

    private

    def receive_line(dp)
      poi = @po.purchase_order_items.find(dp[:purchase_order_item_id])
      qty = BigDecimal(dp[:quantity_received].to_s)
      return if qty <= 0

      batch = StockBatch.create!(
        ingredient: poi.ingredient,
        supplier: @po.supplier,
        quantity_received: qty,
        quantity_remaining: qty,
        cost_per_unit_cents: poi.unit_price_cents,
        received_on: Date.current,
        expires_on: dp[:expires_on].presence,
        batch_reference: dp[:batch_reference]
      )

      StockAdjustment.create!(
        ingredient: poi.ingredient,
        user: @user,
        stock_batch: batch,
        quantity_delta: qty,
        adjustment_type: "delivery",
        reason_notes: "Received via PO #{@po.po_number}"
      )

      total_received = poi.quantity_received.to_d + qty
      poi.update!(
        quantity_received: total_received,
        status: total_received >= poi.quantity_ordered.to_d ? "received" : "partial",
        discrepancy_notes: dp[:discrepancy_notes]
      )

      record_price_history(poi)
    end

    def record_price_history(poi)
      last_price = SupplierPriceHistory
        .where(supplier: @po.supplier, ingredient: poi.ingredient)
        .order(effective_date: :desc)
        .first&.price_cents

      return if last_price == poi.unit_price_cents

      SupplierPriceHistory.create!(
        supplier: @po.supplier,
        ingredient: poi.ingredient,
        price_cents: poi.unit_price_cents,
        effective_date: Date.current,
        recorded_by_user: @user
      )
    end

    def update_po_status
      items = @po.purchase_order_items.reload
      if items.all? { |i| i.status == "received" }
        @po.mark_received! if @po.may_mark_received?
      elsif @po.sent? && @po.may_mark_partially_received?
        @po.mark_partially_received!
      end
    end
  end
end
