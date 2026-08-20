# frozen_string_literal: true

module Inventory
  class VendorInvoiceStockHandler
    class StockConsumedError < StandardError; end

    # Fire a price-change alert when a received price moves more than ±5% from
    # the ingredient's most recent recorded price (across any vendor).
    PRICE_CHANGE_THRESHOLD = 0.05

    def initialize(invoice, user)
      @invoice = invoice
      @user = user
    end

    def receive_line(line)
      location = @invoice.location
      # Convert the entered purchase unit (e.g. gallons) to the base stock unit.
      qty = line.base_quantity
      return if qty <= 0

      ensure_ingredient_at_location!(line.ingredient, location)

      batch = StockBatch.create!(
        ingredient: line.ingredient,
        location: location,
        supplier: @invoice.supplier,
        vendor_invoice_line: line,
        quantity_received: qty,
        quantity_remaining: qty,
        cost_per_unit_cents: line.base_unit_price_cents,
        received_on: @invoice.received_on,
        expires_on: line.expires_on,
        batch_reference: line.batch_reference
      )

      StockAdjustment.create!(
        ingredient: line.ingredient,
        user: @user,
        location: location,
        stock_batch: batch,
        quantity_delta: qty,
        adjustment_type: "vendor_invoice",
        reason_notes: "Received via vendor invoice #{@invoice.invoice_number} at #{location.name}"
      )

      record_price_history(line)
    end

    def reverse_line(line)
      batch = line.stock_batch
      return unless batch

      qty = line.base_quantity
      if batch.quantity_remaining.to_d < qty
        raise StockConsumedError,
          I18n.t("inventory.vendor_invoices.errors.stock_consumed", ingredient: line.ingredient.name)
      end

      location = batch.location || @invoice.location

      StockAdjustment.create!(
        ingredient: line.ingredient,
        user: @user,
        location: location,
        stock_batch: batch,
        quantity_delta: -qty,
        adjustment_type: "vendor_invoice",
        reason_notes: "Reversed vendor invoice #{@invoice.invoice_number} edit"
      )

      # Unlink the batch from this line so receive_line can attach a fresh one.
      batch.update!(quantity_remaining: batch.quantity_remaining.to_d - qty,
                    vendor_invoice_line_id: nil)
    end

    private

    def ensure_ingredient_at_location!(ingredient, location)
      location.ingredient_locations.find_or_create_by!(ingredient: ingredient) do |il|
        il.reorder_threshold = ingredient.reorder_threshold
        il.max_quantity = ingredient.max_quantity
        il.quantity_on_hand = 0
      end
    end

    def record_price_history(line)
      # Track the per-base-unit price so it stays consistent with stock costing.
      price = line.base_unit_price_cents

      # Baseline for the price-change alert: the ingredient's most recent price
      # across ALL vendors, captured before we insert this invoice's row.
      ingredient_last_price = SupplierPriceHistory
        .where(ingredient: line.ingredient)
        .order(effective_date: :desc, created_at: :desc)
        .first&.price_cents

      last_price = SupplierPriceHistory
        .where(supplier: @invoice.supplier, ingredient: line.ingredient)
        .order(effective_date: :desc)
        .first&.price_cents

      # Per-vendor dedup: only store a new row when this supplier's price changed.
      if last_price != price
        SupplierPriceHistory.create!(
          supplier: @invoice.supplier,
          ingredient: line.ingredient,
          price_cents: price,
          effective_date: @invoice.invoice_date,
          recorded_by_user: @user
        )
      end

      notify_significant_price_change(line, ingredient_last_price, price)
    end

    def notify_significant_price_change(line, baseline_cents, new_cents)
      return if baseline_cents.nil? || baseline_cents.zero?

      change_ratio = (new_cents - baseline_cents).abs / baseline_cents.to_d
      return if change_ratio <= PRICE_CHANGE_THRESHOLD

      Inventory::NotifyPriceChangeJob.perform_later(
        line.ingredient_id, @invoice.supplier_id, baseline_cents, new_cents, @invoice.id
      )
    end
  end
end
