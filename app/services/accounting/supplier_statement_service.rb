# frozen_string_literal: true

module Accounting
  # Statement of account for one supplier over a date range: what we owed at the
  # start, every movement on their AP treasury in between, and what we owe at
  # the end.
  #
  # Reads every row on the AP treasury, not just invoices/payments/credit notes,
  # so the closing balance ties to Supplier#ap_balance_cents. Invoices marked
  # historical get no special treatment — they show exactly as the ledger has them.
  #
  # The running balance is recomputed here in date order rather than read from
  # balance_after_cents, which follows insertion order and goes out of sequence
  # as soon as anything is backdated.
  class SupplierStatementService
    Row = Data.define(:transaction, :occurred_on, :kind, :source, :description,
                      :increase_cents, :decrease_cents, :balance_cents)

    Result = Data.define(:start_date, :end_date, :opening_balance_cents, :rows,
                         :total_increase_cents, :total_decrease_cents, :closing_balance_cents)

    def initialize(supplier, start_date:, end_date:)
      @supplier = supplier
      @start_date = start_date
      @end_date = end_date
    end

    def call
      treasury = @supplier.ap_treasury
      return empty_result if treasury.nil?

      transactions = treasury.treasury_transactions
      opening = treasury.opening_balance_cents.to_i +
        transactions.where(occurred_on: ...@start_date).sum(:amount_cents)

      in_range = transactions
        .where(occurred_on: @start_date..@end_date)
        .includes(:source_record)
        .order(:occurred_on, :created_at, :id)
        .to_a
      preload_payment_invoices(in_range)

      running = opening
      rows = in_range.map do |txn|
        running += txn.amount_cents
        Row.new(
          transaction: txn,
          occurred_on: txn.occurred_on,
          kind: txn.kind,
          source: txn.source_record,
          description: txn.description,
          increase_cents: txn.amount_cents.positive? ? txn.amount_cents : 0,
          decrease_cents: txn.amount_cents.negative? ? -txn.amount_cents : 0,
          balance_cents: running
        )
      end

      Result.new(
        start_date: @start_date,
        end_date: @end_date,
        opening_balance_cents: opening,
        rows: rows,
        total_increase_cents: rows.sum(&:increase_cents),
        total_decrease_cents: rows.sum(&:decrease_cents),
        closing_balance_cents: running
      )
    end

    private

    # A legacy invoice payment is shown by its invoice number, so load those
    # invoices in one query instead of one per row.
    def preload_payment_invoices(transactions)
      payments = transactions.map(&:source_record).grep(::VendorInvoicePayment)
      return if payments.empty?

      ActiveRecord::Associations::Preloader.new(records: payments, associations: :vendor_invoice).call
    end

    def empty_result
      Result.new(
        start_date: @start_date,
        end_date: @end_date,
        opening_balance_cents: 0,
        rows: [],
        total_increase_cents: 0,
        total_decrease_cents: 0,
        closing_balance_cents: 0
      )
    end
  end
end
