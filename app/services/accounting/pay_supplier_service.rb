# frozen_string_literal: true

module Accounting
  # Pays a supplier one lump sum and spreads it across their open invoices,
  # oldest first.
  #
  # This replaces the old direct AP payment, which moved the supplier's AP
  # balance without touching a single invoice. That left the invoice list and
  # the AP ledger telling two different stories — by 2026-09 they disagreed by
  # 868,924.29 across 11 suppliers, and every invoice involved still read as
  # unpaid. Routing every payment through real VendorInvoicePayment rows means
  # the two can no longer drift: the ledger balance IS the sum of what the open
  # invoices still owe.
  #
  # Nothing here posts money itself. Each allocation goes through
  # RecordVendorInvoicePaymentService, which already writes the expense, the AP
  # ledger entry, the journal entry and the invoice's payment status.
  class PaySupplierService
    class Error < StandardError; end

    Allocation = Struct.new(:invoice, :amount_cents, keyword_init: true) do
      # True when this allocation closes the invoice outright.
      def settles_invoice?
        amount_cents >= invoice.balance_due_cents
      end
    end

    def initialize(supplier:, user:, treasury:, amount_cents:, payment_date: Date.current)
      @supplier     = supplier
      @user         = user
      @treasury     = treasury
      @amount_cents = amount_cents.to_i
      @payment_date = payment_date
    end

    # The open invoices this supplier can be paid against, oldest first — the
    # order the money is applied in.
    def self.open_invoices_for(supplier)
      supplier.vendor_invoices.posted.outstanding
        .order(invoice_date: :asc, created_at: :asc)
        .select(&:payable?)
    end

    # Splits the amount across open invoices without writing anything. Drives
    # both the confirmation the user sees and the write below, so what they
    # approve is exactly what is recorded.
    def plan
      remaining = @amount_cents
      self.class.open_invoices_for(@supplier).each_with_object([]) do |invoice, allocations|
        next if remaining <= 0

        applied = [remaining, invoice.balance_due_cents].min
        remaining -= applied
        allocations << Allocation.new(invoice: invoice, amount_cents: applied)
      end
    end

    def call
      raise Error, I18n.t("inventory.suppliers.show.pay_supplier.errors.treasury_required") if @treasury.blank?
      raise Error, I18n.t("inventory.suppliers.show.pay_supplier.errors.amount_zero") if @amount_cents <= 0

      open_total = self.class.open_invoices_for(@supplier).sum(&:balance_due_cents)
      raise Error, I18n.t("inventory.suppliers.show.pay_supplier.errors.no_open_invoices") if open_total <= 0

      if @amount_cents > open_total
        raise Error, I18n.t("inventory.suppliers.show.pay_supplier.errors.exceeds_open_invoices",
          amount: helpers.format_money(@amount_cents), open_total: helpers.format_money(open_total))
      end

      allocations = plan

      ActiveRecord::Base.transaction do
        allocations.each do |allocation|
          RecordVendorInvoicePaymentService.new(
            vendor_invoice: allocation.invoice,
            user:           @user,
            treasury:       @treasury,
            amount_cents:   allocation.amount_cents,
            payment_date:   @payment_date
          ).call
        end
      end

      allocations
    end

    private

    def helpers
      ApplicationController.helpers
    end
  end
end
