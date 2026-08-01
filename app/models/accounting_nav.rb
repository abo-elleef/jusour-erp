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
        { controller: "journal_entries",   label: "accounting.nav.journal_entries",   path: :admin_accounting_journal_entries_path,   permission: "accounting:ledgers" },
        { controller: "chart_of_accounts", label: "accounting.nav.chart_of_accounts", path: :admin_accounting_chart_of_accounts_path, permission: "accounting:ledgers" },
        { controller: "fixed_assets",      label: "accounting.nav.fixed_assets",      path: :admin_accounting_fixed_assets_path,      permission: "accounting:ledgers" },
        { controller: "partners",          label: "accounting.nav.partners",          path: :admin_accounting_partners_path,          permission: "accounting:ledgers" },
        { controller: "loans",             label: "accounting.nav.loans",             path: :admin_accounting_loans_path,             permission: "accounting:ledgers" }
      ]
    },
    {
      key: :transactions, icon: :transactions, label: "accounting.nav.groups.transactions",
      tabs: [
        { controller: "expenses",        label: "accounting.nav.expenses",    path: :admin_accounting_expenses_path,          permission: "accounting:transactions" },
        { controller: "incomes",         label: "accounting.nav.incomes",     path: :admin_accounting_incomes_path,           permission: "accounting:transactions" },
        { controller: "monthly_payroll", label: "accounting.nav.payroll",     path: :admin_accounting_monthly_payroll_path,   permission: "payroll:view" },
        { controller: "attendance",      label: "accounting.nav.attendance",  path: :admin_accounting_attendance_path,        permission: "attendance:log" },
        { controller: "shift_logs",      label: "accounting.nav.shifts",      path: :admin_accounting_shift_logs_path,        permission: "attendance:view" },
        { controller: "cash_drawer",     label: "accounting.nav.cash_drawer", path: :admin_accounting_cash_drawer_index_path, permission: "accounting:transactions" },
        { controller: "digital_wallet_day_closes", label: "accounting.nav.digital_wallets", path: :admin_accounting_digital_wallet_day_close_path, permission: "accounting:transactions" },
        { controller: "business_days", label: "accounting.nav.business_days", path: :admin_accounting_business_days_path, permission: "accounting:transactions" }
      ]
    },
    {
      key: :reports, icon: :reports, label: "accounting.nav.groups.reports",
      tabs: [
        { controller: "dashboard",            label: "accounting.nav.dashboard",     path: :admin_accounting_root_path,                                permission: "accounting:reports" },
        { controller: "sales_reports",        label: "accounting.nav.sales",         path: :admin_accounting_sales_reports_path,                       permission: "accounting:reports" },
        { controller: "food_costs",           label: "accounting.nav.food_cost",     path: :admin_accounting_food_costs_path,                          permission: "accounting:reports" },
        { controller: "usage_reports",        label: "accounting.nav.usage",         path: :admin_accounting_usage_reports_path,                       permission: "accounting:reports" },
        { controller: "tax_reports",          label: "accounting.nav.tax",           path: :admin_accounting_tax_reports_path,                         permission: "accounting:reports" },
        { controller: "budgets",              label: "accounting.nav.budgets",       path: :admin_accounting_budgets_path,                             permission: "accounting:reports" },
        { controller: "financial_statements", action: "profit_loss",   label: "accounting.nav.profit_loss",   path: :profit_loss_admin_accounting_financial_statements_path,   permission: "accounting:reports" },
        { controller: "financial_statements", action: "balance_sheet", label: "accounting.nav.balance_sheet", path: :balance_sheet_admin_accounting_financial_statements_path, permission: "accounting:reports" },
        { controller: "financial_statements", action: "cash_flow",     label: "accounting.nav.cash_flow",     path: :cash_flow_admin_accounting_financial_statements_path,     permission: "accounting:reports" }
      ]
    },
    {
      key: :setup, icon: :gear, label: "accounting.nav.groups.setup",
      tabs: [
        { controller: "expense_categories", label: "accounting.nav.expense_categories", path: :admin_accounting_expense_categories_path, permission: "accounting:setup" },
        { controller: "income_categories",  label: "accounting.nav.income_categories",  path: :admin_accounting_income_categories_path,  permission: "accounting:setup" },
        { controller: "discount_rules",      label: "accounting.nav.discounts",          path: :admin_accounting_discount_rules_path,     permission: "accounting:setup" },
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
      # live in the accounting namespace but are surfaced under Settings
      "integrations" => "integrations:manage",
      "payment_method_treasuries" => "payments:manage"
    ).freeze

  def self.permission_for(controller_name)
    CONTROLLER_PERMISSIONS[controller_name]
  end
end
