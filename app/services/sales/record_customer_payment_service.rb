# frozen_string_literal: true

module Sales
  # Takes a payment from a customer by issuing a receipt voucher: cash into the
  # treasury, the customer's receivable drawn down, and the amount applied to
  # their outstanding invoices oldest first.
  #
  # The split is written down rather than inferred. Each invoice the payment
  # touches gets its own allocation, and anything left over is allocated to the
  # customer instead of to an invoice — which is what paying on account means,
  # and keeps the credit on their own receivable where their statement can
  # find it, rather than in a pooled account nobody can trace back to them.
  class RecordCustomerPaymentService
    class Error < StandardError; end

    def initialize(customer:, treasury:, amount_cents:, user:, payment_date: Date.current, notes: nil)
      @customer = customer
      @treasury = treasury
      @amount_cents = amount_cents.to_i
      @user = user
      @payment_date = payment_date
      @notes = notes
    end

    def call
      raise Error, I18n.t("sales.customer_payments.errors.invalid_amount", default: "Payment amount must be positive.") if @amount_cents <= 0
      raise Error, I18n.t("sales.customer_payments.errors.treasury_required", default: "A treasury is required.") if @treasury.blank?

      Accounting::RecordVoucherService.new(
        direction: Voucher::RECEIPT,
        treasury: @treasury,
        user: @user,
        amount_cents: @amount_cents,
        voucher_date: @payment_date,
        counterparty: @customer.display_name,
        notes: @notes,
        company: @customer.company,
        allocations: fifo_allocations
      ).call
    end

    private

    # Oldest invoice first, then whatever is left to the customer's account.
    def fifo_allocations
      remaining = @amount_cents
      allocations = []

      @customer.customer_invoices.outstanding.order(:invoice_date, :created_at).each do |invoice|
        break if remaining <= 0

        applied = [invoice.balance_due_cents, remaining].min
        next if applied <= 0

        allocations << { settles: invoice, amount_cents: applied }
        remaining -= applied
      end

      allocations << { settles: @customer, amount_cents: remaining } if remaining.positive?
      allocations
    end
  end
end
