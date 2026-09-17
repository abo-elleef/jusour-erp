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

  # ── Codes must be fixed per category, not derived from the date filter ──

  describe "stable account codes" do
    let!(:cash) do
      Treasury.create!(name: "Cash", treasury_type: "cash_drawer",
                       balance_cents: 0, opening_balance_cents: 0, company: Current.company)
    end
    let!(:alpha) { IncomeCategory.create!(name: "Alpha", category_type: "sales", company: Current.company) }
    let!(:beta)  { IncomeCategory.create!(name: "Beta", category_type: "services", company: Current.company) }

    def add_income(category, date, cents)
      Income.create!(income_category: category, user: user, treasury: cash,
                     description: "x", amount_cents: cents, income_date: date,
                     recurrence: "one_time", company: Current.company)
    end

    before do
      add_income(alpha, Date.new(2025, 1, 10), 10_000) # only in January
      add_income(beta,  Date.new(2025, 3, 10), 20_000) # only in March
    end

    it "shows each category's own stored code regardless of which categories have activity in the range" do
      jan = described_class.new(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 1, 31))
      mar = described_class.new(start_date: Date.new(2025, 3, 1), end_date: Date.new(2025, 3, 31))

      # Alpha is the only revenue line in January, Beta the only one in March.
      expect(jan.revenue_lines.map(&:name)).to contain_exactly("Alpha")
      expect(mar.revenue_lines.map(&:name)).to contain_exactly("Beta")

      # Beta keeps its own code in March instead of collapsing to 4001 (the old bug).
      beta_line = mar.revenue_lines.first
      expect(beta_line.code).to eq(beta.account_code)
      expect(beta_line.code).not_to eq(4001)
      expect(alpha.account_code).not_to eq(beta.account_code)
    end

    it "matches the code the auto-posted journal entry stamps for the same category" do
      income = add_income(alpha, Date.new(2025, 6, 1), 5_000)
      revenue_line = JournalEntry.for_source(income).first.lines.find { |l| l.account_type == "revenue" }
      expect(revenue_line.account_code).to eq(alpha.account_code)
    end
  end

  # ── Ledger-only liabilities (tax payable, equipment payable) ────────
  #
  # These are posted by JournalEntryService but have no treasury and no model of
  # their own, so before this they were written to the ledger and read by nothing.

  describe "other (ledger-only) liabilities" do
    def create_liability_je(code:, name:, amount_cents:, date:)
      entry = JournalEntry.create!(
        company: Current.company,
        created_by: user,
        entry_number: JournalEntry.next_entry_number(Current.company.id),
        date: date,
        description: "Liability JE #{code}",
        entry_type: "auto"
      )
      entry.lines.create!(account_code: code, account_name: name,
                          account_type: "liability", debit_cents: 0,
                          credit_cents: amount_cents)
      entry.lines.create!(account_code: 9999, account_name: "Offset",
                          account_type: "expense", debit_cents: amount_cents,
                          credit_cents: 0)
      entry
    end

    it "reports tax payable on the balance sheet instead of dropping it" do
      create_liability_je(code: Accounting::JournalEntryService::TAX_PAYABLE_CODE,
                          name: "Tax payable", amount_cents: 7_500,
                          date: Date.current)

      coa = described_class.new(start_date: Date.current.beginning_of_year, end_date: Date.current)

      line = coa.other_liability_lines.find { |l| l.code == 2100 }
      expect(line).to be_present
      expect(line.balance_cents).to eq(7_500)
      expect(coa.total_liabilities_cents).to eq(7_500)
      expect(coa.liability_lines.map(&:code)).to include(2100)
    end

    it "carries a balance owed in an earlier period into the current one" do
      create_liability_je(code: Accounting::JournalEntryService::EQUIPMENT_PAYABLE_CODE,
                          name: "Equipment payable", amount_cents: 40_000,
                          date: 2.years.ago.to_date)

      coa = described_class.new(start_date: Date.current.beginning_of_year, end_date: Date.current)

      expect(coa.other_liability_lines.map(&:code)).to include(2200)
      expect(coa.total_liabilities_cents).to eq(40_000)
    end

    it "nets payments against the balance and drops it once settled" do
      code = Accounting::JournalEntryService::EQUIPMENT_PAYABLE_CODE
      create_liability_je(code: code, name: "Equipment payable",
                          amount_cents: 10_000, date: Date.current)

      entry = JournalEntry.create!(
        company: Current.company, created_by: user,
        entry_number: JournalEntry.next_entry_number(Current.company.id),
        date: Date.current, description: "Settle equipment payable", entry_type: "auto"
      )
      entry.lines.create!(account_code: code, account_name: "Equipment payable",
                          account_type: "liability", debit_cents: 10_000, credit_cents: 0)
      entry.lines.create!(account_code: 9999, account_name: "Offset",
                          account_type: "asset", debit_cents: 0, credit_cents: 10_000)

      coa = described_class.new(start_date: Date.current.beginning_of_year, end_date: Date.current)
      expect(coa.other_liability_lines.map(&:code)).not_to include(code)
    end

    it "does not double-count a loan, which is already reported from its own model" do
      bank = Treasury.create!(name: "Bank", treasury_type: "bank",
                              balance_cents: 100_000, opening_balance_cents: 100_000,
                              company: Current.company)
      loan = Loan.create!(name: "Term Loan", loan_type: "bank_loan",
                          principal_cents: 50_000, company: Current.company)
      Accounting::JournalEntryService.record_loan_disbursement!(
        loan: loan, treasury: bank, amount_cents: 50_000,
        date: Date.current, description: "Disbursed", user: user
      )

      coa = described_class.new(start_date: Date.current.beginning_of_year, end_date: Date.current)

      expect(coa.other_liability_lines.map(&:code)).not_to include(loan.account_code)
      expect(coa.total_liabilities_cents).to eq(coa.loan_liability_lines.sum(&:balance_cents))
    end

    it "does not double-count supplier AP, which is already reported from its treasury" do
      ap = Treasury.create!(name: "Supplier X", treasury_type: "supplier_ap",
                            balance_cents: 0, opening_balance_cents: 0,
                            company: Current.company)
      ap_code = Accounting::JournalEntryService::TREASURY_TYPE_BASE.fetch("supplier_ap") + 1
      create_liability_je(code: ap_code, name: ap.name, amount_cents: 25_000, date: Date.current)

      coa = described_class.new(start_date: Date.current.beginning_of_year, end_date: Date.current)

      expect(coa.other_liability_lines.map(&:code)).not_to include(ap_code)
    end
  end

  # ── Ledger-only current assets ─────────────────────────────────────
  #
  # The asset-side mirror of the liability gap above. 1170 is where income sits
  # once it is booked and before a receipt voucher collects it; without a reader
  # it would accumulate in the ledger and show on no statement.

  describe "other receivables (1170)" do
    def create_receivable_je(amount_cents:, date:, direction: :debit)
      entry = JournalEntry.create!(
        company: Current.company, created_by: user,
        entry_number: JournalEntry.next_entry_number(Current.company.id),
        date: date, description: "Accrued income", entry_type: "auto"
      )
      entry.lines.create!(
        account_code: Accounting::JournalEntryService::OTHER_RECEIVABLES_CODE,
        account_name: "Other receivables", account_type: "asset",
        debit_cents:  direction == :debit ? amount_cents : 0,
        credit_cents: direction == :debit ? 0 : amount_cents
      )
      entry.lines.create!(account_code: 9999, account_name: "Offset",
                          account_type: "revenue",
                          debit_cents:  direction == :debit ? 0 : amount_cents,
                          credit_cents: direction == :debit ? amount_cents : 0)
      entry
    end

    it "reports income booked but not yet collected as a current asset" do
      create_receivable_je(amount_cents: 30_000, date: Date.current)

      coa = described_class.new(start_date: Date.current.beginning_of_year, end_date: Date.current)

      line = coa.current_asset_lines.find { |l| l.code == 1170 }
      expect(line).to be_present
      expect(line.balance_cents).to eq(30_000)
      expect(coa.total_current_assets_cents).to eq(30_000)
    end

    it "still shows a receivable raised in an earlier period" do
      create_receivable_je(amount_cents: 30_000, date: 2.years.ago.to_date)

      coa = described_class.new(start_date: Date.current.beginning_of_year, end_date: Date.current)

      expect(coa.current_asset_lines.map(&:code)).to include(1170)
    end

    it "drops off once collected" do
      create_receivable_je(amount_cents: 30_000, date: Date.current)
      create_receivable_je(amount_cents: 30_000, date: Date.current, direction: :credit)

      coa = described_class.new(start_date: Date.current.beginning_of_year, end_date: Date.current)

      expect(coa.current_asset_lines.map(&:code)).not_to include(1170)
    end
  end
end
