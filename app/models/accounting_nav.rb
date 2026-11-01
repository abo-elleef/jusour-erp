# frozen_string_literal: true

# Single source of truth for the Accounting section's structure AND its
# permissions. The nav partial renders from this (showing only tabs the user
# `can?` see, and landing section/group links on the first accessible tab so a
# click never 403s), and the accounting controllers authorize from the same
# controller→permission map.
module AccountingNav
  # group => { icon:, label:, tabs: [ {controller:, action:, label:, path:, permission:} ] }
  GROUPS = [
    {
      key: :ledgers, icon: :ledgers, label: "accounting.nav.groups.ledgers",
      tabs: [
        { controller: "treasuries",        label: "accounting.nav.treasuries",        path: :admin_accounting_treasuries_path,        permission: "accounting:ledgers" },
      ]
    },
    {
      key: :transactions, icon: :transactions, label: "accounting.nav.groups.transactions",
      tabs: [
        { controller: "expenses",        label: "accounting.nav.expenses",    path: :admin_accounting_expenses_path,          permission: "accounting:transactions" },
        { controller: "incomes",         label: "accounting.nav.incomes",     path: :admin_accounting_incomes_path,           permission: "accounting:transactions" },
        { controller: "vouchers",        label: "accounting.nav.vouchers",    path: :admin_accounting_vouchers_path,          permission: "accounting:transactions" },
        { controller: "monthly_payroll", label: "accounting.nav.payroll",     path: :admin_accounting_monthly_payroll_path,   permission: "payroll:view" },
        { controller: "attendance",      label: "accounting.nav.attendance",  path: :admin_accounting_attendance_path,        permission: "attendance:log", feature: :attendance },
        { controller: "late_penalties",  label: "accounting.nav.late_penalties", path: :admin_accounting_late_penalties_path, permission: "attendance:penalties", feature: :attendance },
        { controller: "shift_logs",      label: "accounting.nav.shifts",      path: :admin_accounting_shift_logs_path,        permission: "attendance:view", feature: :attendance },
        { controller: "cash_drawer",     label: "accounting.nav.cash_drawer", path: :admin_accounting_cash_drawer_index_path, permission: "accounting:day_close" },
        { controller: "digital_wallet_day_closes", label: "accounting.nav.digital_wallets", path: :admin_accounting_digital_wallet_day_close_path, permission: "accounting:day_close" },
        { controller: "business_days", label: "accounting.nav.business_days", path: :admin_accounting_business_days_path, permission: "accounting:day_close" }
      ]
    },
    {
      key: :reports, icon: :reports, label: "accounting.nav.groups.reports",
      tabs: [
        { controller: "dashboard",            label: "accounting.nav.dashboard",     path: :admin_accounting_root_path,                                permission: "accounting:reports",
          description: "accounting.dashboard.description" },
        { controller: "sales_reports",        label: "accounting.nav.sales",         path: :admin_accounting_sales_reports_path,                       permission: "accounting:reports", feature: :menu,
          description: "accounting.sales_reports.description" },
        { controller: "food_costs",           label: "accounting.nav.food_cost",     path: :admin_accounting_food_costs_path,                          permission: "accounting:reports", feature: :menu,
          description: "accounting.food_costs.description" },
        { controller: "usage_reports",        label: "accounting.nav.usage",         path: :admin_accounting_usage_reports_path,                       permission: "accounting:reports", feature: :menu,
          description: "accounting.usage_reports.description" },
        { controller: "tax_reports",          label: "accounting.nav.tax",           path: :admin_accounting_tax_reports_path,                         permission: "accounting:reports", feature: :menu,
          description: "accounting.tax_reports.description" },
        { controller: "category_analysis",    label: "accounting.nav.category_analysis", path: :admin_accounting_category_analysis_index_path,         permission: "accounting:reports",
          description: "accounting.category_analysis.description" },
        { controller: "budgets",              label: "accounting.nav.budgets",       path: :admin_accounting_budgets_path,                             permission: "accounting:reports",
          description: "accounting.budgets.description" },
        { controller: "treasury_movements", label: "accounting.nav.treasury_movements", path: :admin_accounting_treasury_movements_path, permission: "accounting:ledgers",
          description: "accounting.treasury_movements.description" },
        { controller: "kpi_scorecards", label: "accounting.nav.kpi_scorecard", path: :admin_accounting_kpi_scorecard_path, permission: "accounting:reports",
          description: "accounting.kpi.description" },
        { controller: "labour_cost_reports", label: "accounting.nav.labour_cost", path: :admin_accounting_labour_cost_reports_path, permission: "payroll:view",
          description: "accounting.labour_cost.description" },
        { controller: "ledger_reports", action: "trial_balance",  label: "accounting.nav.trial_balance",  path: :trial_balance_admin_accounting_ledger_reports_path,  permission: "accounting:reports",
          description: "accounting.ledger.trial_balance.description" },
        { controller: "ledger_reports", action: "general_ledger", label: "accounting.nav.general_ledger", path: :general_ledger_admin_accounting_ledger_reports_path, permission: "accounting:reports",
          description: "accounting.ledger.general_ledger.description" },
        { controller: "aging_reports", action: "receivable", label: "accounting.nav.ar_aging", path: :receivable_admin_accounting_aging_reports_path, permission: "accounting:reports", feature: :ar_credit_sales,
          description: "accounting.aging.receivable.description" },
        { controller: "aging_reports", action: "payable",    label: "accounting.nav.ap_aging", path: :payable_admin_accounting_aging_reports_path,    permission: "accounting:reports",
          description: "accounting.aging.payable.description" },
        { controller: "financial_statements", action: "balance_sheet", label: "accounting.nav.balance_sheet", path: :balance_sheet_admin_accounting_financial_statements_path, permission: "accounting:reports",
          description: "accounting.financial_statements.balance_sheet_description" },
        { controller: "financial_statements", action: "profit_loss",   label: "accounting.nav.profit_loss",   path: :profit_loss_admin_accounting_financial_statements_path,   permission: "accounting:reports",
          description: "accounting.financial_statements.profit_loss_description" },
        { controller: "financial_statements", action: "cash_flow",     label: "accounting.nav.cash_flow",     path: :cash_flow_admin_accounting_financial_statements_path,     permission: "accounting:reports",
          description: "accounting.cash_flow.description" },
        { controller: "financial_statements", action: "profit_vs_cash", label: "accounting.nav.profit_vs_cash", path: :profit_vs_cash_admin_accounting_financial_statements_path, permission: "accounting:reports",
          description: "accounting.profit_vs_cash.description" }
      ]
    },
    {
      key: :setup, icon: :gear, label: "accounting.nav.groups.setup",
      tabs: [
        { controller: "expense_categories", label: "accounting.nav.expense_categories", path: :admin_accounting_expense_categories_path, permission: "accounting:setup" },
        { controller: "income_categories",  label: "accounting.nav.income_categories",  path: :admin_accounting_income_categories_path,  permission: "accounting:setup" },
        { controller: "discount_rules",      label: "accounting.nav.discounts",          path: :admin_accounting_discount_rules_path,     permission: "accounting:setup" },
        { controller: "journal_entries",   label: "accounting.nav.journal_entries",   path: :admin_accounting_journal_entries_path,   permission: "accounting:ledgers" },
        { controller: "chart_of_accounts", label: "accounting.nav.chart_of_accounts", path: :admin_accounting_chart_of_accounts_path, permission: "accounting:ledgers" },
        { controller: "fixed_assets",      label: "accounting.nav.fixed_assets",      path: :admin_accounting_fixed_assets_path,      permission: "accounting:ledgers" },
        { controller: "partners",          label: "accounting.nav.partners",          path: :admin_accounting_partners_path,          permission: "accounting:ledgers" },
        { controller: "loans",             label: "accounting.nav.loans",             path: :admin_accounting_loans_path,             permission: "accounting:ledgers" },
        { controller: "audit_log",           label: "accounting.nav.audit_log",          path: :admin_accounting_audit_log_index_path,    permission: "accounting:audit" }
      ]
    }
  ].freeze

  # controller_name => required permission, for authorizing accounting controllers.
  # Includes a few controllers that aren't nav tabs but live under the section.
  CONTROLLER_PERMISSIONS = GROUPS.flat_map { |g| g[:tabs] }
    .each_with_object({}) { |t, h| h[t[:controller]] = t[:permission] }
    .merge(
      "treasury_transfers" => "accounting:ledgers",
      "payroll" => "payroll:view",
      "monthly_payroll" => "payroll:view",
      # Reports hub → Staff (ApplicationHelper#staff_report_items)
      "staff_payments_reports" => "payroll:view",
      # live in the accounting namespace but are surfaced under Settings
      "integrations" => "integrations:manage",
      "payment_method_treasuries" => "payments:manage"
    ).freeze

  def self.permission_for(controller_name)
    CONTROLLER_PERMISSIONS[controller_name]
  end
end
