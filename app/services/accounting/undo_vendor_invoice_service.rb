# frozen_string_literal: true

module Accounting
  # Fully undoes a vendor invoice's accounting side-effects:
  #   - payment expenses + cash/bank treasury withdrawals
  #   - supplier AP payment + invoice ledger rows
  #   - related journal entries
  #
  # Stock received from the invoice is intentionally left in place
  # (same behaviour as the previous void action).
  class UndoVendorInvoiceService
    class Error < StandardError; end

    def initialize(invoice:, user:)
      @invoice = invoice
      @user = user
    end

    def call
      raise Error, I18n.t("flash.vendor_invoice.already_void") if @invoice.void?

      ActiveRecord::Base.transaction do
        @invoice.vendor_invoice_payments.includes(:expense).order(created_at: :desc).each do |payment|
          reverse_payment!(payment)
        end

        SupplierApLedgerService.reverse_invoice!(invoice: @invoice, user: @user)
        @invoice.update!(payment_status: "void", amount_paid_cents: 0)
      end

      @invoice
    end

    private

    def reverse_payment!(payment)
      # Destroying the auto-generated expense restores the payment treasury
      # balance via Expense#remove_treasury_ledger.
      payment.expense&.destroy!

      SupplierApLedgerService.reverse_payment!(payment: payment, user: @user)
      payment.destroy!
    end
  end
end
