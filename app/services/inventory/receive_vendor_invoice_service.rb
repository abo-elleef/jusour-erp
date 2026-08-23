# frozen_string_literal: true

module Inventory
  class ReceiveVendorInvoiceService
    def initialize(vendor_invoice, user, freight_amount_cents: 0, freight_treasury: nil,
                   freight_on_account: false)
      @invoice = vendor_invoice
      @user = user
      @freight_amount_cents = freight_amount_cents
      @freight_treasury = freight_treasury
      @freight_on_account = freight_on_account
      @stock_handler = VendorInvoiceStockHandler.new(@invoice, @user)
    end

    def call
      ActiveRecord::Base.transaction do
        @invoice.save!
        @invoice.vendor_invoice_lines.each { |line| @stock_handler.receive_line(line) }
        @invoice.reload
        Accounting::SupplierApLedgerService.record_invoice!(invoice: @invoice, user: @user)
        Accounting::SyncVendorInvoiceFreightService.call(
          invoice: @invoice,
          user: @user,
          amount_cents: @freight_amount_cents,
          treasury: @freight_treasury,
          on_account: @freight_on_account
        )
      end
      @invoice
    end
  end
end
