# frozen_string_literal: true

# Where a Profit & Loss figure should take you when you click it.
#
# Every P&L number is a sum of journal entry lines, so the journal was the only
# honest destination while an entry's source was anyone's guess. It no longer is:
# a category account is written solely by Expense or Income records, and those
# have pages of their own that are far easier to read than a ledger listing.
#
# Only category accounts are rerouted. 5100 is written by vendor invoices, 5500
# by payroll advances and 5501 by payroll snapshots — none of them have an Expense
# record behind them, so sending those figures to the expenses page would open a
# list that cannot add up to the number that was clicked. They stay on the journal,
# which is where their detail actually lives.
module AccountingDrillDownHelper
  def pnl_drill_down_path(account_code, start_date:, end_date:)
    range = { start_date: start_date, end_date: end_date }

    if (category = ExpenseCategory.find_by(account_code: account_code))
      admin_accounting_expenses_path(range.merge(category_id: category.id))
    elsif (category = IncomeCategory.find_by(account_code: account_code))
      admin_accounting_incomes_path(range.merge(category_id: category.id))
    else
      admin_accounting_journal_entries_path(range.merge(account_code: account_code))
    end
  end

  # The hint has to match where the click actually goes, or it promises the ledger
  # and opens a list of expenses.
  def pnl_drill_down_hint(account_code)
    if ExpenseCategory.exists?(account_code: account_code) ||
       IncomeCategory.exists?(account_code: account_code)
      t("accounting.financial_statements.drill_down_records_hint")
    else
      t("accounting.financial_statements.drill_down_hint")
    end
  end

  # The record a treasury movement came from, when it has a page worth opening.
  # A cash flow row is a treasury transaction, and the reader clicking it wants
  # the expense or the income — not the ledger row that mirrors it. Returns nil
  # for movements with no source, or whose source has no page of its own.
  def treasury_source_path(transaction)
    record = transaction.source_record
    return nil if record.nil?

    case record
    when Expense then admin_accounting_expense_path(record)
    when Income  then admin_accounting_income_path(record)
    end
  end
end
