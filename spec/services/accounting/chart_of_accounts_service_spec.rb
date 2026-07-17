# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::ChartOfAccountsService do
  let(:user) { create(:user) }

  # Creates a JournalEntry with a single debit line on the given account code.
  def create_expense_je(code:, amount_cents:, date:)
    entry = JournalEntry.create!(
      company: Current.company,
      created_by: user,
      entry_number: JournalEntry.next_entry_number(Current.company.id),
      date: date,
      description: "Test JE #{code} #{date}",
      entry_type: "auto"
    )
    entry.lines.create!(
      account_code: code,
      account_name: "Test Account",
      account_type: "expense",
      debit_cents: amount_cents,
      credit_cents: 0
    )
    entry.lines.create!(
      account_code: 9999,
      account_name: "Offset",
      account_type: "equity",
      debit_cents: 0,
      credit_cents: amount_cents
    )
  end

  # ── Balance sheet items are never date-filtered ─────────────────────

  describe "current assets (treasury balances)" do
    let!(:cash) do
      Treasury.create!(name: "Cash Box", treasury_type: "cash_drawer",
                       balance_cents: 10_000, opening_balance_cents: 10_000,
                       company: Current.company)
    end

    it "shows the same balance regardless of date range" do
      coa_now  = described_class.new(start_date: Date.current, end_date: Date.current)
      coa_past = described_class.new(start_date: 5.years.ago, end_date: 4.years.ago)

      expect(coa_now.total_current_assets_cents).to eq(10_000)
      expect(coa_past.total_current_assets_cents).to eq(10_000)
    end
  end

  describe "loan liabilities" do
    let!(:cash) do
      Treasury.create!(name: "Bank", treasury_type: "bank",
                       balance_cents: 100_000, opening_balance_cents: 100_000,
                       company: Current.company)
    end

    it "always shows outstanding balance regardless of date range" do
      loan = Loan.create!(
        name: "Term Loan", loan_type: "bank_loan",
        principal_cents: 50_000, company: Current.company
      )
      Accounting::JournalEntryService.record_loan_disbursement!(
        loan: loan, treasury: cash, amount_cents: 50_000,
        date: 3.years.ago.to_date, description: "Disbursed", user: user
      )

      coa_now  = described_class.new(start_date: Date.current, end_date: Date.current)
      coa_past = described_class.new(start_date: 5.years.ago, end_date: 4.years.ago)

      expect(coa_now.total_liabilities_cents).to eq(50_000)
      expect(coa_past.total_liabilities_cents).to eq(50_000)
    end
  end

  # ── Fixed expenses MUST be date-filtered ────────────────────────────

  describe "#fixed_expense_lines date filtering" do
    let(:salary_code) { Accounting::JournalEntryService::SALARY_CODE }
    let(:advance_code) { Accounting::JournalEntryService::ADVANCE_CODE }

    before do
      create_expense_je(code: salary_code, amount_cents: 30_000, date: Date.new(2025, 1, 15))
      create_expense_je(code: salary_code, amount_cents: 30_000, date: Date.new(2025, 3, 15))
      create_expense_je(code: advance_code, amount_cents: 5_000,  date: Date.new(2025, 2, 1))
    end

    it "returns only entries within the date range" do
      coa = described_class.new(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 1, 31))
      salary_line = coa.fixed_expense_lines.find { |l| l.code == salary_code }

      expect(salary_line).not_to be_nil
      expect(salary_line.balance_cents).to eq(30_000)
    end

    it "sums entries across a wider range" do
      coa = described_class.new(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 12, 31))
      salary_line = coa.fixed_expense_lines.find { |l| l.code == salary_code }
      advance_line = coa.fixed_expense_lines.find { |l| l.code == advance_code }

      expect(salary_line.balance_cents).to eq(60_000)
      expect(advance_line.balance_cents).to eq(5_000)
    end

    it "omits accounts with zero total for the period" do
      coa = described_class.new(start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 12, 31))

      expect(coa.fixed_expense_lines).to be_empty
    end

    it "does not bleed across date boundaries" do
      jan_coa = described_class.new(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 1, 31))
      mar_coa = described_class.new(start_date: Date.new(2025, 3, 1), end_date: Date.new(2025, 3, 31))

      jan_salary = jan_coa.fixed_expense_lines.find { |l| l.code == salary_code }
      mar_salary = mar_coa.fixed_expense_lines.find { |l| l.code == salary_code }

      expect(jan_salary.balance_cents).to eq(30_000)
      expect(mar_salary.balance_cents).to eq(30_000)
    end

    it "feeds into net_income correctly" do
      coa_jan = described_class.new(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 1, 31))
      coa_all = described_class.new(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 12, 31))

      # More expense months → higher total expenses → lower (more negative) net income
      expect(coa_all.total_expenses_cents).to be > coa_jan.total_expenses_cents
    end
  end

  # ── Revenue is also date-filtered ───────────────────────────────────

  describe "#revenue_lines date filtering" do
    let!(:cash) do
      Treasury.create!(name: "Cash", treasury_type: "cash_drawer",
                       balance_cents: 0, opening_balance_cents: 0,
                       company: Current.company)
    end
    let!(:category) { IncomeCategory.create!(name: "Sales", category_type: "sales", company: Current.company, position: 1) }

    before do
      Income.create!(income_category: category, user: user, treasury: cash,
                     description: "Jan", amount_cents: 10_000,
                     income_date: Date.new(2025, 1, 10), recurrence: "one_time",
                     company: Current.company)
      Income.create!(income_category: category, user: user, treasury: cash,
                     description: "Mar", amount_cents: 20_000,
                     income_date: Date.new(2025, 3, 10), recurrence: "one_time",
                     company: Current.company)
    end

    it "sums only income within the range" do
      coa = described_class.new(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 1, 31))
      expect(coa.total_revenue_cents).to eq(10_000)
    end

    it "sums all income in a wider range" do
      coa = described_class.new(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 12, 31))
      expect(coa.total_revenue_cents).to eq(30_000)
    end
  end
end
