# frozen_string_literal: true

module Accounting
  class CashFlowService
    # Kinds recorded on asset treasuries that represent real operational cash flows.
    # Excluded: transfer/drawer_open/drawer_reconcile (internal wash),
    #           ap_invoice (non-cash AP accrual),
    #           journal_entry (financing/investing flows already captured via JELs).
    OPERATING_KINDS = %w[income online_payment expense ap_payment
                         payroll_salary payroll_advance staff_meal adjustment].freeze

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
        Section.new(name: :operating, lines: lines)
      end
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

    def net_change_cents
      operating.total_cents + investing.total_cents + financing.total_cents
    end

    def ending_balance_cents
      @ending_balance_cents ||= Treasury
        .active
        .where(company_id: Current.company.id)
        .where.not(treasury_type: "supplier_ap")
        .sum(:balance_cents)
    end

    def beginning_balance_cents
      ending_balance_cents - net_change_cents
    end

    private

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
