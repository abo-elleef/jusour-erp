# frozen_string_literal: true

module Accounting
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

      category = ExpenseCategory.find_by!(name: "Vendor purchases", company: @invoice.company)

      ActiveRecord::Base.transaction do
        payment = VendorInvoicePayment.create!(
          vendor_invoice: @invoice,
          user: @user,
          treasury: @treasury,
          amount_cents: @amount_cents,
          payment_date: @payment_date,
          company: @invoice.company
        )

        expense = Expense.create!(
          expense_category: category,
          user: @user,
          treasury: @treasury,
          description: payment_description,
          amount_cents: @amount_cents,
          expense_date: @payment_date,
          recurrence: "one_time",
          is_auto_generated: true,
          source_record: payment
        )

        @invoice.update!(amount_paid_cents: @invoice.amount_paid_cents + @amount_cents)
        @invoice.sync_payment_status!

        Accounting::SupplierApLedgerService.record_payment!(payment: payment, user: @user)

        payment
      end
    end

    private

    def payment_description
      "Vendor invoice #{@invoice.invoice_number} — #{@invoice.supplier.name}"
    end
  end
end
