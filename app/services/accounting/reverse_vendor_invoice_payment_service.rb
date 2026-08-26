# frozen_string_literal: true

module Accounting
  # Reverses a single vendor invoice payment:
  #   1. Destroys the auto-generated Expense → Expense#remove_treasury_ledger
  #      credits cash back to the paying treasury.
  #   2. Reverses the supplier AP ledger entry for this payment.
  #   3. Reduces invoice.amount_paid_cents and re-syncs payment status
  #      (paid → partial/unpaid as appropriate).
  #   4. Destroys the VendorInvoicePayment record.
  class ReverseVendorInvoicePaymentService
    class Error < StandardError; end

    def initialize(payment:, user:)
      @payment = payment
      @invoice = payment.vendor_invoice
      @user = user
    end

    def call
      raise Error, I18n.t("flash.vendor_invoice.already_void") if @invoice.void?

      ActiveRecord::Base.transaction do
        @payment.expense&.destroy!

        ::Accounting::SupplierApLedgerService.reverse_payment!(payment: @payment, user: @user)

        new_paid = [@invoice.amount_paid_cents - @payment.amount_cents, 0].max
        @invoice.update!(amount_paid_cents: new_paid)
        @invoice.sync_payment_status!

        @payment.destroy!
      end

      @invoice
    end
  end
end
