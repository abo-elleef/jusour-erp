# frozen_string_literal: true

module Accounting
  # The accounts the app owns outright — no model behind them, just a fixed
  # code the whole company shares (accrued expenses, sales clearing, retained
  # earnings, and so on). Same Accountable-shaped #to_account as every real
  # model, so JournalEntryService's debit/credit never has to special-case
  # "this one isn't backed by a row."
  #
  # `account_name` resolves through I18n rather than being stored, same
  # reasoning as JournalEntryService.account_display_name: these names are
  # translations, not user data, so they must read in the viewer's locale,
  # not whichever locale was active when the entry was first posted.
  class SystemAccount
    REGISTRY = {}

    attr_reader :code, :name_key, :account_type, :normal_balance

    def self.register(const_name, code:, name_key:, account_type:, normal_balance:)
      account = new(code: code, name_key: name_key, account_type: account_type, normal_balance: normal_balance)
      REGISTRY[code] = account
      const_set(const_name, account)
    end
    private_class_method :register

    def initialize(code:, name_key:, account_type:, normal_balance:)
      @code = code
      @name_key = name_key
      @account_type = account_type
      @normal_balance = normal_balance
    end

    def account_code = code
    def account_name = I18n.t(name_key)

    def to_account
      AccountRef.new(code: code, name: account_name, account_type: account_type,
                      normal_balance: normal_balance, treasury_id: nil)
    end

    register :EQUITY, code: 3001, account_type: "equity", normal_balance: :credit,
             name_key: "accounting.chart_of_accounts.retained_earnings"
    register :ACCRUED_EXPENSES, code: 2300, account_type: "liability", normal_balance: :credit,
             name_key: "accounting.journal_entries.accounts.accrued_expenses"
    register :OTHER_RECEIVABLES, code: 1170, account_type: "asset", normal_balance: :debit,
             name_key: "accounting.journal_entries.accounts.other_receivables"
    register :SALES_CLEARING, code: 1160, account_type: "asset", normal_balance: :debit,
             name_key: "accounting.journal_entries.accounts.sales_clearing"
    register :EQUIPMENT_PAYABLE, code: 2200, account_type: "liability", normal_balance: :credit,
             name_key: "accounting.journal_entries.accounts.equipment_payable"
    register :TAX_PAYABLE, code: 2100, account_type: "liability", normal_balance: :credit,
             name_key: "accounting.journal_entries.accounts.tax_payable"
    register :SALES_REVENUE, code: 4001, account_type: "revenue", normal_balance: :credit,
             name_key: "accounting.journal_entries.accounts.sales_revenue"
    register :PAYROLL_ADVANCES, code: 5500, account_type: "expense", normal_balance: :debit,
             name_key: "accounting.journal_entries.accounts.payroll_advances"
    register :SALARIES, code: 5501, account_type: "expense", normal_balance: :debit,
             name_key: "accounting.journal_entries.accounts.salaries"
    register :STAFF_MEALS, code: 5502, account_type: "expense", normal_balance: :debit,
             name_key: "accounting.journal_entries.accounts.staff_meals"
    # Not currently posted to by anything — kept only so historical entries
    # written against it (before COGS became its own ExpenseCategory with its
    # own dynamically-assigned code) still resolve a name.
    register :COGS, code: 5503, account_type: "expense", normal_balance: :debit,
             name_key: "accounting.journal_entries.accounts.purchases"
    register :PURCHASES, code: 5100, account_type: "expense", normal_balance: :debit,
             name_key: "accounting.journal_entries.accounts.purchases"
    register :INTEREST_EXPENSE, code: 5600, account_type: "expense", normal_balance: :debit,
             name_key: "accounting.loans.interest_expense_account"
  end
end
