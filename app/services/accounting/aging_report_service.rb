# frozen_string_literal: true

module Accounting
  # Company-wide aging (أعمار الديون): every customer's (receivable) or
  # supplier's (payable) outstanding invoices, bucketed by days past due, beside
  # the party's ledger balance.
  #
  # The two totals differ by whatever sits on the ledger but not against an
  # invoice: opening balances, advances, payments or credit notes not applied to
  # a specific invoice. That gap is shown as "unallocated" rather than dropped,
  # so a party carrying a balance with no open invoice still appears.
  #
  # Due date = invoice date + the customer's credit terms. Suppliers carry no
  # terms, so a payable is due on its invoice date and ages from there.
  class AgingReportService
    SIDES = %i[receivable payable].freeze

    Row = Struct.new(:party, :invoice_count, :buckets, :invoiced_cents, :ledger_cents, :oldest_days,
                     keyword_init: true) do
      def overdue_cents = invoiced_cents - buckets[:not_due]
      def unallocated_cents = ledger_cents - invoiced_cents
    end

    Result = Struct.new(:side, :as_of, :rows, keyword_init: true) do
      def bucket_cents(bucket) = rows.sum { |row| row.buckets[bucket] }
      def invoiced_cents = rows.sum(&:invoiced_cents)
      def overdue_cents = rows.sum(&:overdue_cents)
      def ledger_cents = rows.sum(&:ledger_cents)
      def unallocated_cents = rows.sum(&:unallocated_cents)
      def invoice_count = rows.sum(&:invoice_count)
    end

    def initialize(side, as_of: Date.current, overdue_only: false)
      raise ArgumentError, "unknown side #{side.inspect}" unless SIDES.include?(side)

      @side = side
      @as_of = as_of
      @overdue_only = overdue_only
    end

    def call
      invoices = open_invoices.group_by(&:first)
      ledger = ledger_balances
      party_ids = (invoices.keys + ledger.reject { |_, cents| cents.zero? }.keys).uniq
      parties = party_class.where(id: party_ids).index_by(&:id)
      terms = terms_by_party(party_ids)

      rows = party_ids.filter_map do |id|
        party = parties[id] or next
        build_row(party, invoices.fetch(id, []), terms[id].to_i, ledger[id].to_i)
      end
      rows.select! { |row| row.overdue_cents.positive? } if @overdue_only
      rows.sort_by! { |row| [-row.invoiced_cents, -row.ledger_cents, self.class.party_name(row.party)] }

      Result.new(side: @side, as_of: @as_of, rows: rows)
    end

    def self.party_name(party)
      party.respond_to?(:display_name) ? party.display_name : party.name.to_s
    end

    private

    def build_row(party, invoices, terms_days, ledger_cents)
      buckets = AgingBuckets::ALL.index_with { 0 }
      oldest = 0
      invoices.each do |_, invoice_date, balance_cents|
        overdue = (@as_of - (invoice_date + terms_days.days)).to_i
        buckets[AgingBuckets.for(overdue)] += balance_cents
        oldest = overdue if overdue > oldest
      end

      Row.new(party: party, invoice_count: invoices.size, buckets: buckets,
              invoiced_cents: buckets.values.sum, ledger_cents: ledger_cents, oldest_days: oldest)
    end

    # [party_id, invoice_date, balance_due_cents] for every invoice still owed.
    # Each side's `outstanding` scope already leaves out drafts, voids and paid
    # invoices; the positive-balance check guards against an overpaid invoice
    # whose status has not been re-synced.
    def open_invoices
      rows = if receivable?
               CustomerInvoice.outstanding.pluck(
                 :customer_id, :invoice_date,
                 Arel.sql("customer_invoices.total_cents - customer_invoices.amount_paid_cents")
               )
             else
               VendorInvoice.posted.outstanding.pluck(
                 :supplier_id, :invoice_date,
                 Arel.sql("vendor_invoices.total_cents - vendor_invoices.amount_paid_cents " \
                          "- vendor_invoices.credit_applied_cents - vendor_invoices.historical_settled_cents")
               )
             end
      rows.select { |row| row.last.to_i.positive? }.map { |id, date, cents| [id, date, cents.to_i] }
    end

    # Positive = owed: a customer's AR treasury balance is what they owe us, a
    # supplier's AP treasury balance is what we owe them.
    def ledger_balances
      scope = receivable? ? Treasury.customer_ar : Treasury.supplier_ap
      column = receivable? ? :customer_id : :supplier_id
      scope.where.not(column => nil).group(column).sum(:balance_cents)
    end

    def terms_by_party(party_ids)
      return {} unless receivable?

      Customer.where(id: party_ids).pluck(:id, :credit_terms_days).to_h
    end

    def party_class
      receivable? ? Customer : Supplier
    end

    def receivable?
      @side == :receivable
    end
  end
end
