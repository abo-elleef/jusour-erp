# frozen_string_literal: true

module Inventory
  class ReceiveVendorInvoiceService
    def initialize(vendor_invoice, user)
      @invoice = vendor_invoice
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        @invoice.save!
        @invoice.vendor_invoice_lines.each do |line|
          receive_line(line)
        end
        @invoice.update_column(:total_cents, @invoice.vendor_invoice_lines.sum(&:line_total_cents))
      end
      @invoice
    end

    private

    def receive_line(line)
      qty = line.quantity.to_d
      return if qty <= 0

      batch = StockBatch.create!(
        ingredient: line.ingredient,
        supplier: @invoice.supplier,
        vendor_invoice_line: line,
        quantity_received: qty,
        quantity_remaining: qty,
        cost_per_unit_cents: line.unit_price_cents,
        received_on: @invoice.received_on,
        expires_on: line.expires_on,
        batch_reference: line.batch_reference
      )

      StockAdjustment.create!(
        ingredient: line.ingredient,
        user: @user,
        stock_batch: batch,
        quantity_delta: qty,
        adjustment_type: "vendor_invoice",
        reason_notes: "Received via vendor invoice #{@invoice.invoice_number}"
      )

      record_price_history(line)
    end

    def record_price_history(line)
      last_price = SupplierPriceHistory
        .where(supplier: @invoice.supplier, ingredient: line.ingredient)
        .order(effective_date: :desc)
        .first&.price_cents

      return if last_price == line.unit_price_cents

      SupplierPriceHistory.create!(
        supplier: @invoice.supplier,
        ingredient: line.ingredient,
        price_cents: line.unit_price_cents,
        effective_date: @invoice.invoice_date,
        recorded_by_user: @user
      )
    end
  end
end
