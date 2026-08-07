# frozen_string_literal: true

module Inventory
  class UpdateVendorInvoiceService
    class Error < StandardError; end

    def initialize(vendor_invoice, user, attributes, freight_amount_cents: 0, freight_treasury: nil)
      @invoice = vendor_invoice
      @user = user
      @attributes = attributes
      @freight_amount_cents = freight_amount_cents
      @freight_treasury = freight_treasury
      @stock_handler = VendorInvoiceStockHandler.new(@invoice, @user)
    end

    def call
      raise Error, I18n.t("inventory.vendor_invoices.errors.not_editable") unless @invoice.fully_editable?

      ActiveRecord::Base.transaction do
        lines_to_reverse = @invoice.vendor_invoice_lines.includes(:stock_batch, :ingredient).to_a

        lines_to_reverse.each { |line| @stock_handler.reverse_line(line) }
        Accounting::SupplierApLedgerService.reverse_invoice!(invoice: @invoice, user: @user)

        @invoice.assign_attributes(@attributes)
        @invoice.save!

        @invoice.vendor_invoice_lines.each { |line| @stock_handler.receive_line(line) }
        @invoice.reload
        Accounting::SupplierApLedgerService.record_invoice!(invoice: @invoice, user: @user)
        Accounting::SyncVendorInvoiceFreightService.call(
          invoice: @invoice,
          user: @user,
          amount_cents: @freight_amount_cents,
          treasury: @freight_treasury
        )
      end

      @invoice
    rescue VendorInvoiceStockHandler::StockConsumedError => e
      raise Error, e.message
    end
  end
end
