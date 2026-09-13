# frozen_string_literal: true

module Accounting
  # Bridges the two numbers owners most often think should match and don't:
  # the P&L's net profit and the cash flow statement's net change in cash.
  #
  # Profit answers "what did we earn", cash answers "what moved through the
  # safe". Every line below is a place where those two legitimately diverge —
  # money spent that is not an expense (stock, drawings, assets), or an expense
  # that has not been paid yet.
  #
  # Both ends are taken from the statements themselves rather than recomputed,
  # so the bridge can never disagree with the pages it is explaining. Anything
  # the named lines fail to account for is surfaced as `residual_cents` instead
  # of being quietly absorbed — a bridge that always "closes" by construction
  # would tell you nothing.
  class ProfitVsCashService
    Line = Struct.new(:key, :amount_cents, :hint_values, keyword_init: true) do
      def zero? = amount_cents.zero?
    end

    VENDOR_PURCHASES_CATEGORY = "Vendor purchases"

    def initialize(start_date:, end_date:)
      @start_date = start_date
      @end_date   = end_date
    end

    # ── The two ends ──────────────────────────────────────────────────────

    # Identical arithmetic to the P&L page: revenue − (opening + purchases −
    # closing) − operating expenses. Inventory comes from the manual snapshots,
    # not the ledger, which is exactly why a ledger-only bridge cannot close.
    def net_profit_cents
      @net_profit_cents ||= gross_profit_cents - coa.total_operating_expenses_cents
    end

    def gross_profit_cents
      @gross_profit_cents ||= coa.total_revenue_cents - cogs_cents
    end

    def cogs_cents
      @cogs_cents ||= opening_inventory_cents + coa.purchases_cents - closing_inventory_cents
    end

    def cash_change_cents
      @cash_change_cents ||= cash_flow.net_change_cents
    end

    # ── The bridge ────────────────────────────────────────────────────────

    # Signed as "effect on cash relative to profit": negative means cash left
    # without profit noticing, positive means profit was charged without cash
    # leaving. Zero lines are dropped — an empty row explains nothing.
    def lines
      @lines ||= [
        Line.new(key: :inventory_build, amount_cents: -inventory_movement_cents,
                 hint_values: { opening: opening_inventory_cents, closing: closing_inventory_cents }),
        Line.new(key: :unpaid_purchases, amount_cents: unpaid_purchases_cents,
                 hint_values: { purchases: coa.purchases_cents, paid: vendor_cash_paid_cents }),
        Line.new(key: :financing, amount_cents: cash_flow.financing.total_cents),
        Line.new(key: :investing, amount_cents: cash_flow.investing.total_cents),
        Line.new(key: :equity_adjustments, amount_cents: equity_adjustments_cents),
        Line.new(key: :advance_timing, amount_cents: -advance_timing_cents,
                 hint_values: { paid: advances_paid_cents, expensed: advances_expensed_cents }),
        Line.new(key: :digital_payments, amount_cents: digital_payments_cents),
        Line.new(key: :ledger_only_expenses, amount_cents: ledger_only_expenses_cents,
                 hint_values: { ledger: coa.total_other_expense_cents, records: non_vendor_expense_records_cents })
      ].reject(&:zero?)
    end

    # Whatever the named lines do not explain. Should be zero; when it is not,
    # it is pointing at something real (a manual journal entry straight to an
    # equity or liability account, a reversal spanning the period boundary).
    def residual_cents
      @residual_cents ||= cash_change_cents - net_profit_cents - lines.sum(&:amount_cents)
    end

    def balanced?
      residual_cents.zero?
    end

    # ── Components ────────────────────────────────────────────────────────

    # Stock bought but not yet sold. Profit only ever saw the part that was
    # consumed (closing inventory reduces COGS); the cash went out regardless.
    def inventory_movement_cents
      @inventory_movement_cents ||= closing_inventory_cents - opening_inventory_cents
    end

    # Goods invoiced by suppliers but not yet settled: charged to Purchases
    # (5100) so profit is already down, while the money has not moved.
    def unpaid_purchases_cents
      @unpaid_purchases_cents ||= coa.purchases_cents - vendor_cash_paid_cents
    end

    # Both settlement paths — a payment against an invoice and a direct payment
    # against a supplier's standing balance — land in this one category.
    def vendor_cash_paid_cents
      @vendor_cash_paid_cents ||= expense_records_in_period
        .joins(:expense_category)
        .where(expense_categories: { name: VENDOR_PURCHASES_CATEGORY })
        .sum(:amount_cents)
    end

    # Cash moved straight against Retained Earnings rather than any revenue or
    # expense account, so the P&L never sees it.
    def equity_adjustments_cents
      @equity_adjustments_cents ||= asset_treasury_transactions.where(kind: "adjustment").sum(:amount_cents)
    end

    # An advance is paid in one period and charged in another often enough to
    # be worth naming rather than leaving in the residual.
    def advance_timing_cents
      @advance_timing_cents ||= advances_paid_cents - advances_expensed_cents
    end

    def advances_paid_cents
      @advances_paid_cents ||= asset_treasury_transactions.where(kind: "payroll_advance").sum(:amount_cents).abs
    end

    def advances_expensed_cents
      @advances_expensed_cents ||= journal_lines
        .where(account_code: ::Accounting::JournalEntryService::ADVANCE_CODE)
        .sum("debit_cents - credit_cents")
    end

    # Card and wallet takings clear Sales clearing (1160) rather than crediting
    # revenue, so they are cash arriving against revenue recognised elsewhere.
    def digital_payments_cents
      @digital_payments_cents ||= asset_treasury_transactions.where(kind: "online_payment").sum(:amount_cents)
    end

    # Operating expense on the P&L with no expense record behind it, because it
    # was posted straight to the ledger — loan interest, delivery billed on a
    # vendor invoice, or an entry written by hand. Those charge profit in a
    # period where no cash left, which is a real divergence.
    #
    def ledger_only_expenses_cents
      @ledger_only_expenses_cents ||= coa.total_other_expense_cents - non_vendor_expense_records_cents
    end

    # Every expense record in the period. There is no longer a second state to
    # filter out: an expense that should not stand is deleted, not flagged, so
    # the rows here and the journal entries they wrote move together.
    def active_expense_records_cents
      @active_expense_records_cents ||= expense_records_in_period.sum(:amount_cents)
    end

    def expense_records_in_period
      Expense
        .where(company_id: Current.company.id)
        .where(expense_date: @start_date..@end_date)
    end

    def non_vendor_expense_records_cents
      @non_vendor_expense_records_cents ||= active_expense_records_cents - vendor_cash_paid_cents
    end

    def opening_inventory_cents
      @opening_inventory_cents ||= opening_snapshot&.value_cents.to_i
    end

    def closing_inventory_cents
      @closing_inventory_cents ||= closing_snapshot&.value_cents.to_i
    end

    def opening_snapshot
      load_snapshots
      @opening_snapshot
    end

    def closing_snapshot
      load_snapshots
      @closing_snapshot
    end

    def coa
      @coa ||= ::Accounting::ChartOfAccountsService.new(start_date: @start_date, end_date: @end_date)
    end

    def cash_flow
      @cash_flow ||= ::Accounting::CashFlowService.new(start_date: @start_date, end_date: @end_date)
    end

    private

    # Same rule the P&L uses, including the guard for a range so short that both
    # ends resolve to the same snapshot — counting it twice would invent an
    # inventory movement of exactly zero and hide a real one.
    def load_snapshots
      return if defined?(@snapshots_loaded)

      @opening_snapshot = InventorySnapshot.where(company: Current.company).on_or_before(@start_date).first
      @closing_snapshot = InventorySnapshot.where(company: Current.company).on_or_before(@end_date).first
      @opening_snapshot = nil if @opening_snapshot && @closing_snapshot &&
                                 @opening_snapshot.id == @closing_snapshot.id
      @snapshots_loaded = true
    end

    def asset_treasury_transactions
      ::TreasuryTransaction
        .joins(:treasury)
        .where(treasuries: { company_id: Current.company.id })
        .where.not(treasuries: { treasury_type: "supplier_ap" })
        .where(occurred_on: @start_date..@end_date)
    end

    def journal_lines
      ::JournalEntryLine
        .joins(:journal_entry)
        .where(journal_entries: { company_id: Current.company.id, date: @start_date..@end_date })
    end
  end
end
