# frozen_string_literal: true

module Accounting
  class CashFlowService
    # Kinds recorded on asset treasuries that represent real operational cash flows.
    # Excluded: transfer/drawer_open/drawer_reconcile (internal wash),
    #           ap_invoice (non-cash AP accrual).
    OPERATING_KINDS = %w[income online_payment expense ap_payment
                         payroll_salary payroll_advance staff_meal adjustment].freeze

    # Cash moved by a journal entry — a reversal, or an entry written by hand.
    # Reported separately rather than folded into a kind above, because the
    # entries behind it are heterogeneous and the reader deserves to see how
    # much of the period's cash moved this way.
    #
    # This used to be dropped entirely, on the grounds that financing reads loan
    # and partner flows straight from the journal. That is true of those two
    # accounts and nothing else, so every reversal silently vanished: reversing
    # an expense restores the cash with a `journal_entry` transaction, while the
    # original outflow stays put. The statement showed the money leaving and
    # never showed it come back. Entries touching a financing account are still
    # excluded here — those really would be counted twice.
    JOURNAL_ENTRY_KIND = "journal_entry"

    # Buying a machine is investing, not operating — and only the cash that actually
    # moved counts. Deliberately excluded from OPERATING_KINDS above.
    INVESTING_KINDS = %w[fixed_asset_purchase fixed_asset_payment].freeze

    CashFlowLine = Struct.new(:label, :amount_cents, :kind, keyword_init: true)

    Section = Struct.new(:name, :lines, keyword_init: true) do
      def total_cents
        lines.sum(&:amount_cents)
      end
    end

    def initialize(start_date:, end_date:)
      @start_date = start_date
      @end_date   = end_date
    end

    # ── Operating ─────────────────────────────────────────────────────────

    def operating
      @operating ||= begin
        grouped = asset_transactions.where(kind: OPERATING_KINDS).group(:kind).sum(:amount_cents)
        lines = OPERATING_KINDS.filter_map do |kind|
          cents = grouped[kind].to_i
          next if cents.zero?
          CashFlowLine.new(
            label:        I18n.t("accounting.cash_flow.kinds.#{kind}"),
            amount_cents: cents,
            kind:         kind
          )
        end
        je_cents = journal_entry_cash_cents
        unless je_cents.zero?
          lines << CashFlowLine.new(
            label:        I18n.t("accounting.cash_flow.kinds.#{JOURNAL_ENTRY_KIND}"),
            amount_cents: je_cents,
            kind:         JOURNAL_ENTRY_KIND
          )
        end
        Section.new(name: :operating, lines: lines)
      end
    end

    # Journal-entry cash, minus anything the financing section already reports
    # from the journal itself.
    def journal_entry_cash_cents
      @journal_entry_cash_cents ||= journal_entry_transactions.sum(:amount_cents)
    end

    def journal_entry_transactions
      scope = asset_transactions.where(kind: JOURNAL_ENTRY_KIND)
      ids   = financing_journal_entry_ids
      return scope if ids.empty?

      # NULL-safe on purpose: a transaction with no source entry cannot be one
      # of the financing entries, and a bare NOT IN would silently drop it.
      scope.where("treasury_transactions.source_record_id IS NULL OR treasury_transactions.source_record_id NOT IN (?)", ids)
    end

    # ── Investing ─────────────────────────────────────────────────────────

    # Read from the treasury ledger, not the FixedAsset register.
    #
    # The register booked the full purchase price as an outflow on the purchase date,
    # which was wrong twice over: a machine bought on credit had not cost any cash
    # yet, and once a purchase also created an Expense to reconcile the safe, the same
    # machine appeared here AND in operating. Actual cash movements fix both.
    def investing
      @investing ||= begin
        grouped = asset_transactions.where(kind: INVESTING_KINDS).group(:kind).sum(:amount_cents)
        lines = INVESTING_KINDS.filter_map do |kind|
          cents = grouped[kind].to_i
          next if cents.zero?

          CashFlowLine.new(
            label:        I18n.t("accounting.cash_flow.kinds.#{kind}"),
            amount_cents: cents,
            kind:         kind
          )
        end
        Section.new(name: :investing, lines: lines)
      end
    end

    # ── Financing ─────────────────────────────────────────────────────────

    def financing
      @financing ||= begin
        lines = loan_lines + partner_lines
        Section.new(name: :financing, lines: lines)
      end
    end

    # ── Totals ────────────────────────────────────────────────────────────

    # What the three sections manage to classify.
    def classified_change_cents
      @classified_change_cents ||= operating.total_cents + investing.total_cents + financing.total_cents
    end

    # What the treasuries actually did. Every balance change is driven by a
    # treasury transaction, so summing them *is* the movement — which makes this
    # the honest figure to headline, and the yardstick the sections are measured
    # against.
    def net_change_cents
      @net_change_cents ||= all_transactions_in_range.sum(:amount_cents)
    end

    # Real movement the sections could not account for. Should be zero. When it
    # is not, the statement is now able to say so instead of hiding it — which
    # is the whole point of measuring the opening balance rather than deriving
    # it from the very total being checked.
    def unclassified_cents
      @unclassified_cents ||= net_change_cents - classified_change_cents
    end

    def balanced?
      unclassified_cents.zero?
    end

    # Built from the ledger, not from today's balances. `Treasury#balance_cents`
    # is a live figure: reading it for a period that has already closed reports
    # the balance now, not the balance then — so a statement for last month was
    # anchored to this month's cash.
    def beginning_balance_cents
      @beginning_balance_cents ||= opening_float_cents + movement_before_start_cents
    end

    def ending_balance_cents
      @ending_balance_cents ||= beginning_balance_cents + net_change_cents
    end

    private

    def operating_treasuries
      @operating_treasuries ||= Treasury
        .where(company_id: Current.company.id)
        .where.not(treasury_type: "supplier_ap")
    end

    def opening_float_cents
      @opening_float_cents ||= operating_treasuries.sum(:opening_balance_cents)
    end

    def movement_before_start_cents
      @movement_before_start_cents ||= non_ap_transactions
        .where(occurred_on: ...@start_date)
        .sum(:amount_cents)
    end

    # Every kind, not just the classified ones — this has to equal the balance
    # movement, so nothing may be filtered out of it.
    def all_transactions_in_range
      non_ap_transactions.where(occurred_on: @start_date..@end_date)
    end

    def non_ap_transactions
      TreasuryTransaction
        .joins(:treasury)
        .where(treasuries: { company_id: Current.company.id })
        .where.not(treasuries: { treasury_type: "supplier_ap" })
    end

    # Entries the financing section already reports by reading the journal, so
    # their treasury side must not be counted again in operating.
    def financing_journal_entry_ids
      @financing_journal_entry_ids ||= begin
        codes = Loan.where(company_id: Current.company.id).pluck(:account_code) +
                Partner.where(company_id: Current.company.id).pluck(:account_code)
        if codes.empty?
          []
        else
          JournalEntryLine.where(account_code: codes).distinct.pluck(:journal_entry_id).compact
        end
      end
    end

    # Asset-treasury transactions in the date range (excludes supplier_ap).
    def asset_transactions
      TreasuryTransaction
        .joins(:treasury)
        .where(treasuries: { company_id: Current.company.id })
        .where.not(treasuries: { treasury_type: "supplier_ap" })
        .where(occurred_on: @start_date..@end_date)
    end

    # JournalEntryLines restricted to the date range.
    def je_lines_in_range
      @je_lines_in_range ||= JournalEntryLine
        .joins(:journal_entry)
        .where(journal_entries: { company_id: Current.company.id, date: @start_date..@end_date })
    end

    def loan_lines
      Loan.where(company_id: Current.company.id).flat_map do |loan|
        scope   = je_lines_in_range.where(account_code: loan.account_code)
        credits = scope.sum(:credit_cents)
        debits  = scope.sum(:debit_cents)
        lines   = []

        if credits > 0
          lines << CashFlowLine.new(
            label:        I18n.t("accounting.cash_flow.loan_proceeds", name: loan.name),
            amount_cents: credits,
            kind:         "loan_proceeds"
          )
        end

        if debits > 0
          lines << CashFlowLine.new(
            label:        I18n.t("accounting.cash_flow.loan_repayment", name: loan.name),
            amount_cents: -debits,
            kind:         "loan_repayment"
          )
        end

        lines
      end
    end

    def partner_lines
      Partner.where(company_id: Current.company.id).flat_map do |partner|
        scope   = je_lines_in_range.where(account_code: partner.account_code)
        credits = scope.sum(:credit_cents)
        debits  = scope.sum(:debit_cents)
        lines   = []

        if credits > 0
          lines << CashFlowLine.new(
            label:        I18n.t("accounting.cash_flow.capital_contribution", name: partner.name),
            amount_cents: credits,
            kind:         "capital_contribution"
          )
        end

        if debits > 0
          lines << CashFlowLine.new(
            label:        I18n.t("accounting.cash_flow.partner_drawings", name: partner.name),
            amount_cents: -debits,
            kind:         "partner_drawings"
          )
        end

        lines
      end
    end
  end
end
