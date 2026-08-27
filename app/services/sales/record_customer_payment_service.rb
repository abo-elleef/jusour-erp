# frozen_string_literal: true

module Sales
  # Records a customer payment: settles the AR ledger (cash into the treasury,
  # Dr treasury / Cr AR) and allocates the amount FIFO across the customer's
  # outstanding invoices (oldest first), updating each invoice's paid amount and
  # status. Any leftover reduces the AR balance anyway (an on-account credit).
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

      payment = nil
      ActiveRecord::Base.transaction do
        payment = CustomerPayment.create!(
          company: @customer.company, customer: @customer, user: @user,
          treasury: @treasury, amount_cents: @amount_cents, payment_date: @payment_date, notes: @notes
        )
        Accounting::CustomerArLedgerService.new(@customer).settle!(
          treasury: @treasury, amount_cents: @amount_cents, user: @user,
          occurred_on: @payment_date, source: payment
        )
        allocate_fifo!
      end
      payment
    end

    private

    # Apply the payment to the oldest outstanding invoices first.
    def allocate_fifo!
      remaining = @amount_cents
      @customer.customer_invoices.outstanding.order(:invoice_date, :created_at).each do |invoice|
        break if remaining <= 0

        applied = [invoice.balance_due_cents, remaining].min
        next if applied <= 0

        invoice.update!(amount_paid_cents: invoice.amount_paid_cents + applied)
        invoice.sync_payment_status!
        remaining -= applied
      end
    end
  end
end
