# frozen_string_literal: true

module Sales
  # Marks a confirmed delivery invoice as handed to its shipping company.
  #
  # For cash-on-delivery this is the moment the shipping company becomes
  # accountable for the order value — nobody held our cash before now, so
  # this is also where revenue gets recognised (see
  # Accounting::ShippingCompanyLedgerService#charge!). For a delivery that
  # already settled online, dispatch is a pure fulfillment stamp — the money
  # reached a treasury straight from the customer at approval time, and the
  # shipping company never touches it.
  class DispatchCustomerInvoiceService
    class Error < StandardError; end

    def initialize(invoice, user)
      @invoice = invoice
      @user = user
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        if @invoice.cash_on_delivery?
          Accounting::ShippingCompanyLedgerService.new(@invoice.shipping_company).charge!(
            amount_cents: @invoice.total_cents, user: @user,
            occurred_on: Date.current, source: @invoice
          )
          @invoice.update!(dispatched_at: Time.current, payment_status: "paid",
                           amount_paid_cents: @invoice.total_cents)
        else
          @invoice.update!(dispatched_at: Time.current)
        end
      end

      @invoice
    end

    private

    def validate!
      raise Error, I18n.t("sales.customer_invoices.errors.not_confirmed", default: "Only a confirmed invoice can be dispatched.") unless @invoice.confirmed?
      raise Error, I18n.t("sales.customer_invoices.errors.not_delivery", default: "Only a delivery invoice can be dispatched.") unless @invoice.delivery?
      raise Error, I18n.t("sales.customer_invoices.errors.no_shipping_company", default: "A shipping company is required before dispatch.") if @invoice.shipping_company.blank?
      raise Error, I18n.t("sales.customer_invoices.errors.already_dispatched", default: "This invoice was already dispatched.") if @invoice.dispatched?
    end
  end
end
