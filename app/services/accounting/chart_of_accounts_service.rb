# frozen_string_literal: true

module Accounting
  # Assembles a live Chart of Accounts from existing treasury, income, and
  # expense data. Read-only — no new tables required. Relies on Tenantable
  # default scopes being active (Current.company must be set by the caller).
  class ChartOfAccountsService
    AccountLine = Struct.new(
      :code, :name, :account_type, :subtype, :balance_cents, :normal_balance,
      keyword_init: true
    )

    ASSET_BASE_CODES = {
      "cash_drawer"   => 1000,
      "bank"          => 1100,
      "safe"          => 1200,
      "petty_cash"    => 1300,
      "mobile_wallet" => 1400,
      "other"         => 1500
    }.freeze

    def asset_lines
      @asset_lines ||= begin
        counters = Hash.new(0)
        non_ap_treasuries.map do |t|
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

    def liability_lines
      @liability_lines ||= ap_treasuries.each_with_index.map do |t, i|
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

    def equity_lines
      @equity_lines ||= [
        AccountLine.new(
          code:           3001,
          name:           I18n.t("accounting.chart_of_accounts.retained_earnings"),
          account_type:   :equity,
          subtype:        "retained_earnings",
          balance_cents:  total_equity_cents,
          normal_balance: :credit
        )
      ]
    end

    def revenue_lines
      @revenue_lines ||= income_totals.each_with_index.map do |(category_name, cents), i|
        AccountLine.new(
          code:           4001 + i,
          name:           category_name,
          account_type:   :revenue,
          subtype:        "income",
          balance_cents:  cents,
          normal_balance: :credit
        )
      end
    end

    def expense_lines
      @expense_lines ||= expense_totals.each_with_index.map do |(category_name, cents), i|
        AccountLine.new(
          code:           5001 + i,
          name:           category_name,
          account_type:   :expense,
          subtype:        "expense",
          balance_cents:  cents,
          normal_balance: :debit
        )
      end
    end

    def total_assets_cents
      @total_assets_cents ||= asset_lines.sum(&:balance_cents)
    end

    def total_liabilities_cents
      @total_liabilities_cents ||= liability_lines.sum(&:balance_cents)
    end

    def total_equity_cents
      # Recomputed directly to avoid circular memoization with equity_lines
      @total_equity_cents ||= total_assets_cents - total_liabilities_cents
    end

    def total_revenue_cents
      @total_revenue_cents ||= revenue_lines.sum(&:balance_cents)
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
      @income_totals ||= Income
        .joins(:income_category)
        .group("income_categories.name")
        .order("income_categories.name")
        .sum(:amount_cents)
    end

    def expense_totals
      @expense_totals ||= Expense
        .joins(:expense_category)
        .group("expense_categories.name")
        .order("expense_categories.name")
        .sum(:amount_cents)
    end
  end
end
