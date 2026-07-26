# frozen_string_literal: true

module Accounting
  # Builds a grouped list of all accounts available for manual journal entry selection.
  # Returns groups compatible with Rails grouped_options_for_select.
  class AccountListService
    EQUITY_ACCOUNT = { code: 3001, name_key: "accounting.chart_of_accounts.retained_earnings" }.freeze

    FIXED_EXPENSE_ACCOUNTS = [
      { code: JournalEntryService::ADVANCE_CODE,    name_key: "accounting.journal_entries.accounts.payroll_advances" },
      { code: JournalEntryService::SALARY_CODE,     name_key: "accounting.journal_entries.accounts.salaries" },
      { code: JournalEntryService::STAFF_MEAL_CODE, name_key: "accounting.journal_entries.accounts.staff_meals" },
      { code: JournalEntryService::COGS_CODE,       name_key: "accounting.journal_entries.accounts.purchases" },
      { code: JournalEntryService::INTEREST_CODE,   name_key: "accounting.loans.interest_expense_account" }
    ].freeze

    # Returns array of [group_label, [[display, value], ...]] for grouped_options_for_select
    def call
      [
        asset_group,
        liability_group,
        equity_group,
        revenue_group,
        expense_group
      ].reject { |_label, options| options.empty? }
    end

    private

    def asset_group
      options = Treasury.active
                        .where.not(treasury_type: "supplier_ap")
                        .order(:position, :name)
                        .map { |t| [treasury_label(t), encode(:treasury, t.id, t.name, "asset")] }
      [ I18n.t("accounting.journal_entries.account_types.asset"), options ]
    end

    def liability_group
      ap_options = Treasury.active
                           .where(treasury_type: "supplier_ap")
                           .order(:name)
                           .map { |t| [treasury_label(t), encode(:treasury, t.id, t.name, "liability")] }
      loan_options = Loan.active.ordered.map do |l|
        [ "#{l.account_code}  #{l.account_name}", encode(:loan, l.id, l.account_name, "liability") ]
      end
      [ I18n.t("accounting.journal_entries.account_types.liability"), ap_options + loan_options ]
    end

    def equity_group
      name = I18n.t(EQUITY_ACCOUNT[:name_key])
      retained = [ "#{EQUITY_ACCOUNT[:code]}  #{name}", encode(:equity, nil, name, "equity") ]
      partner_options = Partner.active.ordered.map do |p|
        [ "#{p.account_code}  #{p.account_name}", encode(:partner, p.id, p.account_name, "equity") ]
      end
      [ I18n.t("accounting.journal_entries.account_types.equity"), [retained] + partner_options ]
    end

    def revenue_group
      options = IncomeCategory.ordered.map do |cat|
        [ "#{cat.account_code}  #{cat.name}", encode(:income_category, cat.id, cat.name, "revenue") ]
      end
      [ I18n.t("accounting.journal_entries.account_types.revenue"), options ]
    end

    def expense_group
      dynamic = ExpenseCategory.ordered.map do |cat|
        [ "#{cat.account_code}  #{cat.name}", encode(:expense_category, cat.id, cat.name, "expense") ]
      end
      fixed = FIXED_EXPENSE_ACCOUNTS.map do |acct|
        name = I18n.t(acct[:name_key])
        [ "#{acct[:code]}  #{name}", encode(:fixed_expense, acct[:code], name, "expense") ]
      end
      [ I18n.t("accounting.journal_entries.account_types.expense"), dynamic + fixed ]
    end

    # Encode all account info into the option value so the controller can decode it
    # Format: "type|id_or_code|name|account_type"
    def encode(kind, id, name, account_type)
      "#{kind}|#{id}|#{name}|#{account_type}"
    end

    def treasury_label(treasury)
      base = JournalEntryService::TREASURY_TYPE_BASE.fetch(treasury.treasury_type, 1500)
      siblings = Treasury.unscoped.where(company_id: treasury.company_id,
                                         treasury_type: treasury.treasury_type)
                         .order(:position, :name)
      idx = siblings.pluck(:id).index(treasury.id).to_i
      code = base + idx + 1
      "#{code}  #{treasury.name}"
    end
  end
end
