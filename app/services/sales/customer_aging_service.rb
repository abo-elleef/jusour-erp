# frozen_string_literal: true

module Sales
  # AR aging for a customer: buckets each outstanding invoice's balance by how far
  # past its due date it is (due date = invoice_date + credit terms). Also returns
  # the per-invoice rows and the ledger balance for reconciliation.
  class CustomerAgingService
    BUCKETS = ::Accounting::AgingBuckets::ALL

    Row = Struct.new(:invoice, :due_date, :days_overdue, :bucket, :balance_cents, keyword_init: true)
    Result = Struct.new(:customer, :as_of, :buckets, :rows, :total_cents, :ledger_balance_cents, keyword_init: true)

    def initialize(customer, as_of: Date.current)
      @customer = customer
      @as_of = as_of
    end

    def call
      terms = @customer.credit_terms_days.to_i
      buckets = BUCKETS.index_with { 0 }
      rows = @customer.customer_invoices.outstanding.order(:invoice_date, :created_at).map do |invoice|
        due = invoice.invoice_date + terms.days
        overdue = (@as_of - due).to_i
        bucket = ::Accounting::AgingBuckets.for(overdue)
        buckets[bucket] += invoice.balance_due_cents
        Row.new(invoice: invoice, due_date: due, days_overdue: [overdue, 0].max,
                bucket: bucket, balance_cents: invoice.balance_due_cents)
      end

      Result.new(customer: @customer, as_of: @as_of, buckets: buckets, rows: rows,
                 total_cents: buckets.values.sum, ledger_balance_cents: @customer.ar_balance_cents)
    end
  end
end
