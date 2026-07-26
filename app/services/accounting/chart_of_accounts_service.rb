# frozen_string_literal: true

module Accounting
  # Assembles a live Chart of Accounts from existing treasury, income, and
  # expense data. Read-only — no new tables required. Relies on Tenantable
  # default scopes being active (Current.company must be set by the caller).
  class ChartOfAccountsService
    attr_reader :start_date, :end_date

    def initialize(start_date: nil, end_date: nil)
      @start_date = start_date
      @end_date   = end_date
    end

    AccountLine = Struct.new(
      :code, :name, :account_type, :subtype, :balance_cents, :normal_balance,
      keyword_init: true
    )

    CURRENT_ASSET_TYPES = %w[cash_drawer bank safe petty_cash mobile_wallet other].freeze

    ASSET_BASE_CODES = {
      "cash_drawer"   => 1000,
      "bank"          => 1100,
      "safe"          => 1200,
      "petty_cash"    => 1300,
      "mobile_wallet" => 1400,
      "other"         => 1500
    }.freeze

    FIXED_ASSET_BASE_CODES = {
      "equipment"             => 1600,
      "furniture"             => 1700,
      "vehicle"               => 1800,
      "property"              => 1900,
      "leasehold_improvement" => 1950,
      "other"                 => 1980
    }.freeze

    FIXED_EXPENSE_ACCOUNTS = [
      { code: JournalEntryService::ADVANCE_CODE,   name_key: "accounting.journal_entries.accounts.payroll_advances" },
      { code: JournalEntryService::SALARY_CODE,    name_key: "accounting.journal_entries.accounts.salaries" },
      { code: JournalEntryService::STAFF_MEAL_CODE, name_key: "accounting.journal_entries.accounts.staff_meals" },
      { code: JournalEntryService::COGS_CODE,      name_key: "accounting.journal_entries.accounts.purchases" },
      { code: JournalEntryService::INTEREST_CODE,  name_key: "accounting.loans.interest_expense_account" }
    ].freeze

    # ── Current assets ────────────────────────────────────────────────

    def current_asset_lines
      @current_asset_lines ||= begin
        counters = Hash.new(0)
        non_ap_treasuries.select { |t| CURRENT_ASSET_TYPES.include?(t.treasury_type) }.map do |t|
          base = ASSET_BASE_CODES.fetch(t.treasury_type, 1500)
          counters[base] += 1
          AccountLine.new(
            code:           base + counters[base],
            name:           t.name,
            account_type:   :asset,
            subtype:        t.treasury_type,
            balance_cents:  t.balance_cents,
            normal_balance: :debit
          )
        end
      end
    end

    def total_current_assets_cents
      @total_current_assets_cents ||= current_asset_lines.sum(&:balance_cents)
    end

    # ── Non-current assets (fixed assets) ────────────────────────────

    def non_current_asset_lines
      @non_current_asset_lines ||= begin
        counters = Hash.new(0)
        FixedAsset.active.ordered.map do |fa|
          base = FIXED_ASSET_BASE_CODES.fetch(fa.asset_type, 1980)
          counters[base] += 1
          AccountLine.new(
            code:           base + counters[base],
            name:           fa.name,
            account_type:   :asset,
            subtype:        fa.asset_type,
            balance_cents:  fa.current_value_cents,
            normal_balance: :debit
          )
        end
      end
    end

    def total_non_current_assets_cents
      @total_non_current_assets_cents ||= non_current_asset_lines.sum(&:balance_cents)
    end

    def asset_lines
      @asset_lines ||= current_asset_lines + non_current_asset_lines
    end

    def total_assets_cents
      @total_assets_cents ||= total_current_assets_cents + total_non_current_assets_cents
    end

    # ── Accounts Payable (supplier AP, 2001+) ─────────────────────────

    def ap_liability_lines
      @ap_liability_lines ||= ap_treasuries.each_with_index.map do |t, i|
        AccountLine.new(
          code:           2001 + i,
          name:           t.name,
          account_type:   :liability,
          subtype:        "accounts_payable",
          balance_cents:  t.balance_cents,
          normal_balance: :credit
        )
      end
    end

    # ── Loans (2100+) ─────────────────────────────────────────────────

    def loan_liability_lines
      @loan_liability_lines ||= Loan.ordered.map do |loan|
        AccountLine.new(
          code:           loan.account_code,
          name:           loan.name,
          account_type:   :liability,
          subtype:        loan.loan_type,
          balance_cents:  loan.outstanding_balance_cents,
          normal_balance: :credit
        )
      end
    end

    def liability_lines
      @liability_lines ||= ap_liability_lines + loan_liability_lines
    end

    def total_liabilities_cents
      @total_liabilities_cents ||= liability_lines.sum(&:balance_cents)
    end

    # ── Equity ────────────────────────────────────────────────────────

    def partner_equity_lines
      @partner_equity_lines ||= Partner.ordered.map do |partner|
        AccountLine.new(
          code:           partner.account_code,
          name:           partner.name,
          account_type:   :equity,
          subtype:        "partner_account",
          balance_cents:  partner.balance_cents,
          normal_balance: :credit
        )
      end
    end

    def total_partner_equity_cents
      @total_partner_equity_cents ||= partner_equity_lines.sum(&:balance_cents)
    end

    # Retained Earnings = total equity residual after partner current accounts
    def retained_earnings_cents
      @retained_earnings_cents ||= total_equity_cents - total_partner_equity_cents
    end

    def equity_lines
      @equity_lines ||= begin
        retained = AccountLine.new(
          code:           3001,
          name:           I18n.t("accounting.chart_of_accounts.retained_earnings"),
          account_type:   :equity,
          subtype:        "retained_earnings",
          balance_cents:  retained_earnings_cents,
          normal_balance: :credit
        )
        [retained] + partner_equity_lines
      end
    end

    # Assets - Liabilities (now includes loans, so balance sheet holds)
    def total_equity_cents
      @total_equity_cents ||= total_assets_cents - total_liabilities_cents
    end

    # ── Revenue ───────────────────────────────────────────────────────

    def revenue_lines
      @revenue_lines ||= income_totals.map do |(code, category_name), cents|
        AccountLine.new(
          code:           code,
          name:           category_name,
          account_type:   :revenue,
          subtype:        "income",
          balance_cents:  cents,
          normal_balance: :credit
        )
      end
    end

    def total_revenue_cents
      @total_revenue_cents ||= revenue_lines.sum(&:balance_cents)
    end

    # ── Expenses — dynamic categories ────────────────────────────────

    def dynamic_expense_lines
      @dynamic_expense_lines ||= expense_totals.map do |(code, category_name), cents|
        AccountLine.new(
          code:           code,
          name:           category_name,
          account_type:   :expense,
          subtype:        "expense",
          balance_cents:  cents,
          normal_balance: :debit
        )
      end
    end

    # ── Expenses — fixed system accounts (payroll, COGS, interest) ───

    def fixed_expense_lines
      @fixed_expense_lines ||= begin
        je_scope = JournalEntryLine.joins(:journal_entry)
                                   .where(journal_entries: { company_id: Current.company.id })
        if @start_date && @end_date
          je_scope = je_scope.where(journal_entries: { date: @start_date..@end_date })
        end
        FIXED_EXPENSE_ACCOUNTS.filter_map do |acct|
          total = je_scope.where(account_code: acct[:code]).sum(:debit_cents)
          next if total == 0

          AccountLine.new(
            code:           acct[:code],
            name:           I18n.t(acct[:name_key]),
            account_type:   :expense,
            subtype:        "fixed_expense",
            balance_cents:  total,
            normal_balance: :debit
          )
        end
      end
    end

    def expense_lines
      @expense_lines ||= dynamic_expense_lines + fixed_expense_lines
    end

    def total_expenses_cents
      @total_expenses_cents ||= expense_lines.sum(&:balance_cents)
    end

    def net_income_cents
      @net_income_cents ||= total_revenue_cents - total_expenses_cents
    end

    private

    def non_ap_treasuries
      @non_ap_treasuries ||= Treasury
        .active
        .where.not(treasury_type: "supplier_ap")
        .order(:position, :name)
    end

    def ap_treasuries
      @ap_treasuries ||= Treasury
        .active
        .where(treasury_type: "supplier_ap")
        .order(:name)
    end

    def income_totals
      @income_totals ||= begin
        scope = Income.joins(:income_category)
        scope = scope.on_date_range(@start_date, @end_date) if @start_date && @end_date
        scope.group("income_categories.account_code", "income_categories.name")
             .order("income_categories.account_code")
             .sum(:amount_cents)
      end
    end

    def expense_totals
      @expense_totals ||= begin
        scope = Expense.joins(:expense_category)
        scope = scope.on_date_range(@start_date, @end_date) if @start_date && @end_date
        scope.group("expense_categories.account_code", "expense_categories.name")
             .order("expense_categories.account_code")
             .sum(:amount_cents)
      end
    end
  end
end
