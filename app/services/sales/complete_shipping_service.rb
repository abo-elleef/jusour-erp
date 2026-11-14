# frozen_string_literal: true

module Sales
  # Marks a shipped delivery as delivered: someone checked the courier's own
  # system and it shows the order handed to the customer.
  #
  # Pure fulfillment stamp — no money moves. The courier's balance was already
  # settled at dispatch (COD charge + delivery-fee accrual), and returns go
  # through a customer credit note, not through this.
  class CompleteShippingService
    class Error < StandardError; end

    def initialize(invoice, user)
      @invoice = invoice
      @user = user
    end

    def call
      unless @invoice.confirmed? && @invoice.shipped?
        raise Error, I18n.t("sales.customer_invoices.errors.not_shipped",
                            default: "Only an invoice that is with the shipping company can be marked delivered.")
      end

      @invoice.update!(shipping_status: "shipping_completed",
                       shipping_completed_at: Time.current,
                       shipping_completed_by: @user)
      @invoice
    end
  end
end
