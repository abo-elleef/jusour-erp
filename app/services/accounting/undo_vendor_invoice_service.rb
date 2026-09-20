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
        @invoice.payment_vouchers.to_a.each { |voucher| voucher.void!(user: @user, reason: :invoice_undone) }

        clear_freight_expense!

        SupplierApLedgerService.reverse_invoice!(invoice: @invoice, user: @user)
        @invoice.update!(payment_status: "void", amount_paid_cents: 0)
      end

      @invoice
    end

    private

    def clear_freight_expense!
      expense = @invoice.freight_expense
      return unless expense

      JournalEntryService.destroy_for_source!(expense)
      expense.destroy!
    end

  end
end
