# frozen_string_literal: true

module Inventory
  class ReceiveVendorInvoiceService
    def initialize(vendor_invoice, user)
      @invoice = vendor_invoice
      @user = user
      @stock_handler = VendorInvoiceStockHandler.new(@invoice, @user)
    end

    def call
      ActiveRecord::Base.transaction do
        @invoice.save!
        @invoice.vendor_invoice_lines.each { |line| @stock_handler.receive_line(line) }
        @invoice.reload
        Accounting::SupplierApLedgerService.record_invoice!(invoice: @invoice, user: @user)
      end
      @invoice
    end
  end
end
