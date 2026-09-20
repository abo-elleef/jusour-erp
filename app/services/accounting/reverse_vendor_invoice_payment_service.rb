# frozen_string_literal: true

module Accounting
  # Reverses one supplier payment by voiding the voucher that made it.
  #
  # Everything the payment did hangs off that voucher, so voiding it undoes the
  # lot: the cash goes back to the treasury it left, the supplier's payable is
  # restored, the invoice's paid-to-date is given back and its status re-synced,
  # and the journal entry is removed. This used to unwind four records by hand.
  class ReverseVendorInvoicePaymentService
    class Error < StandardError; end

    def initialize(payment:, user:)
      @voucher = payment
      @invoice = payment.payment_allocations.map(&:settles).compact.find { |s| s.is_a?(VendorInvoice) }
      @user = user
    end

    def call
      raise Error, I18n.t("flash.vendor_invoice.already_void") if @invoice&.void?

      ActiveRecord::Base.transaction { @voucher.void!(user: @user, reason: :reversed) }

      @invoice&.reload
    end
  end
end
