# frozen_string_literal: true

module Accounting
  # Pays a supplier invoice by issuing a payment voucher against it.
  #
  # This used to write three records for one event: a VendorInvoicePayment, an
  # auto-generated Expense that existed only to move the cash and show the
  # payment in the expenses list, and an AP ledger entry. The Expense was never
  # an expense — the goods are charged to Purchases (5100) when the invoice is
  # received — and having two writers for one payment is what let the ledger
  # credit cash twice without the treasury noticing.
  #
  # Now there is one record. The voucher moves the cash, draws down the
  # supplier's payable, updates the invoice and posts the entry, all through
  # RecordVoucherService, and the payment is a document the accountant can print.
  class RecordVendorInvoicePaymentService
    class Error < StandardError; end

    def initialize(vendor_invoice:, user:, treasury:, amount_cents:, payment_date: Date.current)
      @invoice = vendor_invoice
      @user = user
      @treasury = treasury
      @amount_cents = amount_cents.to_i
      @payment_date = payment_date
    end

    def call
      raise Error, "Invoice cannot accept payments" unless @invoice.payable?
      raise Error, "Payment amount must be greater than zero" if @amount_cents <= 0
      raise Error, "Payment amount exceeds balance due" if @amount_cents > @invoice.balance_due_cents

      RecordVoucherService.new(
        direction: Voucher::PAYMENT,
        treasury: @treasury,
        user: @user,
        amount_cents: @amount_cents,
        voucher_date: @payment_date,
        counterparty: @invoice.supplier.name,
        notes: payment_description,
        company: @invoice.company,
        allocations: [{ settles: @invoice, amount_cents: @amount_cents }]
      ).call
    end

    private

    def payment_description
      "#{I18n.t('accounting.vouchers.settles', default: 'Settles')}: #{@invoice.invoice_number}"
    end
  end
end
