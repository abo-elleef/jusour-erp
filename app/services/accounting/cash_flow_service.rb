# frozen_string_literal: true

module Accounting
  class CashFlowService
    # Kinds recorded on asset treasuries that represent real operational cash flows.
    #
    # `drawer_reconcile` belongs here despite the name: it banks
    # `counted_cash_cents - opening_float_cents` — the cash customers actually paid
    # during the session — and records that one leg only. It was excluded as an
    # "internal wash", which it never was. `drawer_open` is the wash: it records both
    # the leg leaving the safe and the leg entering the drawer, so the pair nets to
    # zero. The giveaway was `online_payment`, which is raised by the very same
    # session and was counted here all along, so a session's card and wallet takings
    # reached the statement while its cash silently fell into the unclassified line.
    #
    # Excluded: transfer/drawer_open (internal wash), ap_invoice (non-cash AP accrual).
    #
    # `voucher_receipt` / `voucher_payment` are cash moved by a سند قبض / سند صرف.
    # They sit here rather than replacing `income`/`expense` because the older
    # rows keep those kinds: an expense used to move its own cash, and the
    # statement has to keep reading both for periods that straddle the change.
    OPERATING_KINDS = %w[income online_payment drawer_reconcile expense ap_payment
                         payroll_salary payroll_advance staff_meal adjustment
                         voucher_receipt voucher_payment].freeze

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

    CashFlowLine = Struct.new(:label, :amount_cents, :kind, :account_code, keyword_init: true)

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
        # Its own line, never folded into the expense line above. That line answers
        # "what did we pay out in expenses", and it has to be built from Expense
        # records alone to answer it — cash arriving because an entry was written or
        # reversed is a different question and gets its own row.
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

    # The transactions behind one line. The journal-entry line excludes whatever the
    # financing section already reports, so its drill-down has to exclude the same
    # rows — a line whose rows do not add up to it is worse than no drill-down.
    def transactions_for_kind(kind)
      return journal_entry_transactions if kind == JOURNAL_ENTRY_KIND

      asset_transactions.where(kind: kind)
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

    # The journal-entry cash movements whose entry touches this account. Public
    # so the drill-down can list exactly the rows that make up the line.
    def financing_transactions_for(account_code)
      ids = JournalEntryLine.where(account_code: account_code)
                            .distinct.pluck(:journal_entry_id).compact
      return TreasuryTransaction.none if ids.empty?

      asset_transactions.where(kind: JOURNAL_ENTRY_KIND,
                               source_record_type: "JournalEntry", source_record_id: ids)
    end

    private

    def operating_treasuries
      @operating_treasuries ||= Treasury
        .where(company_id: Current.company.id)
        .where.not(treasury_type: Treasury::LEDGER_TYPES)
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

    # Excludes both AP and AR ledger treasuries: neither one is real cash, only
    # a running balance of what's owed — their own invoice/payment/credit-note
    # legs would otherwise leak into the cash totals as unclassified noise.
    def non_ap_transactions
      TreasuryTransaction
        .joins(:treasury)
        .where(treasuries: { company_id: Current.company.id })
        .where.not(treasuries: { treasury_type: Treasury::LEDGER_TYPES })
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

    # Asset-treasury transactions in the date range (excludes AP/AR ledgers).
    def asset_transactions
      TreasuryTransaction
        .joins(:treasury)
        .where(treasuries: { company_id: Current.company.id })
        .where.not(treasuries: { treasury_type: Treasury::LEDGER_TYPES })
        .where(occurred_on: @start_date..@end_date)
    end

    def loan_lines
      Loan.where(company_id: Current.company.id).flat_map do |loan|
        financing_lines_for(
          loan.account_code, name: loan.name,
          inflow:  { key: "accounting.cash_flow.loan_proceeds",  kind: "loan_proceeds" },
          outflow: { key: "accounting.cash_flow.loan_repayment", kind: "loan_repayment" }
        )
      end
    end

    def partner_lines
      Partner.where(company_id: Current.company.id).flat_map do |partner|
        financing_lines_for(
          partner.account_code, name: partner.name,
          inflow:  { key: "accounting.cash_flow.capital_contribution", kind: "capital_contribution" },
          outflow: { key: "accounting.cash_flow.partner_drawings",     kind: "partner_drawings" }
        )
      end
    end

    # Built from cash that actually moved, not from the journal lines on the
    # account. Those lines say what an entry was *about*; they do not say
    # whether any money changed hands. An entry that debited a loan and credited
    # an expense account was being reported here as a repayment, so the section
    # claimed an outflow the treasuries never saw — the statement inventing cash
    # is exactly the failure this report exists to catch.
    #
    # Direction comes from the movement itself: money arriving is a drawdown or
    # a contribution, money leaving is a repayment or a drawing.
    def financing_lines_for(account_code, name:, inflow:, outflow:)
      txns = financing_transactions_for(account_code)
      received = txns.where("treasury_transactions.amount_cents > 0").sum(:amount_cents)
      paid     = txns.where("treasury_transactions.amount_cents < 0").sum(:amount_cents)
      lines    = []

      if received.positive?
        lines << CashFlowLine.new(label: I18n.t(inflow[:key], name: name), amount_cents: received,
                                  kind: inflow[:kind], account_code: account_code)
      end
      if paid.negative?
        lines << CashFlowLine.new(label: I18n.t(outflow[:key], name: name), amount_cents: paid,
                                  kind: outflow[:kind], account_code: account_code)
      end
      lines
    end

  end
end
