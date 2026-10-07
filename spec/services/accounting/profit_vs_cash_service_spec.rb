# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::ProfitVsCashService do
  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:start_date) { Date.current.beginning_of_month }
  let(:end_date)   { Date.current.end_of_month }

  let!(:cash) do
    Treasury.create!(name: "Cash Drawer", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0, company: company)
  end

  subject(:bridge) { described_class.new(start_date: start_date, end_date: end_date) }

  def journal(description:, date: Date.current, &block)
    entry = JournalEntry.create!(company: company, created_by: owner, date: date,
                                 description: description,
                                 entry_number: "JE-#{SecureRandom.hex(4)}")
    block.call(entry)
    entry
  end

  def post(entry, code:, name:, type:, debit: 0, credit: 0)
    entry.lines.create!(account_code: code, account_name: name, account_type: type,
                        debit_cents: debit, credit_cents: credit)
  end

  # Mirrors sync_je_treasuries!: an entry that moves cash also writes a
  # journal_entry transaction against the treasury, which is what makes the
  # measured cash movement agree with the ledger.
  def je_treasury_txn(entry, amount_cents:)
    TreasuryTransaction.create!(treasury: cash, user: owner, amount_cents: amount_cents,
                                kind: "journal_entry", description: entry.description,
                                occurred_on: entry.date, source_record: entry,
                                balance_after_cents: 0, company: company)
  end

  def treasury_txn(kind:, amount_cents:)
    TreasuryTransaction.create!(treasury: cash, user: owner, amount_cents: amount_cents,
                                kind: kind, description: kind, occurred_on: Date.current,
                                balance_after_cents: 0, company: company)
  end

  describe "the two ends" do
    before do
      journal(description: "Sales") { |e| post(e, code: 4001, name: "Sales", type: "revenue", credit: 1_000_00) }
      journal(description: "Purchases") { |e| post(e, code: 5100, name: "Purchases", type: "expense", debit: 400_00) }
      journal(description: "Rent") { |e| post(e, code: 5027, name: "Rent", type: "expense", debit: 100_00) }
    end

    it "computes net profit the same way the P&L page does" do
      # Revenue 1000 − COGS (0 + 400 − 0) − operating expenses 100 = 500.
      expect(bridge.net_profit_cents).to eq(500_00)
      expect(bridge.gross_profit_cents).to eq(600_00)
      expect(bridge.cogs_cents).to eq(400_00)
    end

    it "takes the cash figure from the cash flow statement itself" do
      treasury_txn(kind: "income", amount_cents: 1_000_00)
      treasury_txn(kind: "expense", amount_cents: -100_00)

      expect(bridge.cash_change_cents).to eq(
        Accounting::CashFlowService.new(start_date: start_date, end_date: end_date).net_change_cents
      )
    end
  end

  describe "the reconciling lines" do
    def line(key)
      bridge.lines.find { |l| l.key == key }
    end

    it "charges stock bought but not sold against cash, not profit" do
      InventorySnapshot.create!(company: company, snapshot_date: start_date - 1, value_cents: 100_00)
      InventorySnapshot.create!(company: company, snapshot_date: end_date, value_cents: 250_00)

      expect(bridge.inventory_movement_cents).to eq(150_00)
      expect(line(:inventory_build).amount_cents).to eq(-150_00)
    end

    it "adds back supplier invoices charged to profit but not yet paid" do
      journal(description: "Purchases") { |e| post(e, code: 5100, name: "Purchases", type: "expense", debit: 500_00) }
      category = ExpenseCategory.find_or_create_by!(name: "Vendor purchases", company: company) do |c|
        c.category_type = "other"
        c.position = 99
      end
      Expense.create!(expense_category: category, user: owner, treasury: cash,
                      description: "Paid vendor", amount_cents: 300_00, expense_date: Date.current,
                      recurrence: "one_time", is_auto_generated: true, company: company)

      expect(bridge.vendor_cash_paid_cents).to eq(300_00)
      expect(line(:unpaid_purchases).amount_cents).to eq(200_00)
    end

    it "subtracts owner drawings, which never reach the P&L" do
      partner = Partner.create!(company: company, name: "Owner", ownership_percentage: 100)
      entry = journal(description: "Drawing") do |e|
        post(e, code: partner.account_code, name: "Owner", type: "equity", debit: 400_00)
        post(e, code: 1001, name: "Cash", type: "asset", credit: 400_00)
      end
      je_treasury_txn(entry, amount_cents: -400_00)

      expect(line(:financing).amount_cents).to eq(-400_00)
    end

    it "subtracts cash adjustments booked straight to equity" do
      treasury_txn(kind: "adjustment", amount_cents: -60_00)

      expect(line(:equity_adjustments).amount_cents).to eq(-60_00)
    end

    it "names the gap between advances paid and advances charged" do
      # advances_expensed_cents reads PayrollAdvance directly (see its comment
      # in profit_vs_cash_service.rb) rather than a ledger code — each advance
      # now posts to its own employee's account, which the ledger alone can no
      # longer tell apart from that same employee's salary or staff meals.
      treasury_txn(kind: "payroll_advance", amount_cents: -80_00)
      staff = create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)
      PayrollAdvance.create!(user: staff, treasury: cash, paid_by: owner,
                             amount_cents: 50_00, paid_on: Date.current)

      expect(line(:advance_timing).amount_cents).to eq(-30_00)
    end

    it "counts card takings as cash against revenue recognised elsewhere" do
      treasury_txn(kind: "online_payment", amount_cents: 17_00)

      expect(line(:digital_payments).amount_cents).to eq(17_00)
    end

    it "names P&L expense that has no expense record behind it" do
      journal(description: "Loan interest") { |e| post(e, code: 5600, name: "Interest", type: "expense", debit: 45_00) }

      expect(bridge.ledger_only_expenses_cents).to eq(45_00)
      expect(line(:ledger_only_expenses).amount_cents).to eq(45_00)
    end

    it "drops lines with nothing to say" do
      expect(bridge.lines.map(&:key)).not_to include(:investing)
    end
  end

  describe "closing the bridge" do
    # The owner's real August shape: profitable on paper, far less cash in hand,
    # because stock was built, suppliers were left unpaid and the owners drew.
    before do
      journal(description: "Sales") { |e| post(e, code: 4001, name: "Sales", type: "revenue", credit: 3_000_00) }
      journal(description: "Purchases") { |e| post(e, code: 5100, name: "Purchases", type: "expense", debit: 1_800_00) }
      journal(description: "Rent") { |e| post(e, code: 5027, name: "Rent", type: "expense", debit: 200_00) }

      InventorySnapshot.create!(company: company, snapshot_date: start_date - 1, value_cents: 500_00)
      InventorySnapshot.create!(company: company, snapshot_date: end_date, value_cents: 700_00)

      category = ExpenseCategory.find_or_create_by!(name: "Vendor purchases", company: company) do |c|
        c.category_type = "other"
        c.position = 99
      end
      Expense.create!(expense_category: category, user: owner, treasury: cash,
                      description: "Paid vendors", amount_cents: 1_500_00, expense_date: Date.current,
                      recurrence: "one_time", is_auto_generated: true, company: company)

      treasury_txn(kind: "income", amount_cents: 3_000_00)
      treasury_txn(kind: "adjustment", amount_cents: -10_00)

      partner = Partner.create!(company: company, name: "Owner", ownership_percentage: 100)
      entry = journal(description: "Drawing") do |e|
        post(e, code: partner.account_code, name: "Owner", type: "equity", debit: 250_00)
        post(e, code: 1001, name: "Cash", type: "asset", credit: 250_00)
      end
      je_treasury_txn(entry, amount_cents: -250_00)

      # Rent was posted by journal entry with no expense record behind it, and
      # the cash for it left as an ordinary expense transaction — the pair the
      # ledger-only and reversed-entry lines exist to name.
      rent_category = ExpenseCategory.find_or_create_by!(name: "Rent", company: company) do |c|
        c.category_type = "other"
        c.position = 98
      end
      Expense.create!(expense_category: rent_category, user: owner, treasury: cash,
                      description: "Rent", amount_cents: 200_00, expense_date: Date.current,
                      recurrence: "one_time", is_auto_generated: true, company: company)
    end

    it "walks from profit to cash with nothing left over" do
      expect(bridge).to be_balanced
      expect(bridge.residual_cents).to eq(0)
      expect(bridge.net_profit_cents + bridge.lines.sum(&:amount_cents)).to eq(bridge.cash_change_cents)
    end

    it "names every part of the gap" do
      expect(bridge.lines.map(&:key)).to include(
        :inventory_build, :unpaid_purchases, :financing, :equity_adjustments
      )
    end

    it "surfaces anything the named lines miss instead of hiding it" do
      # A manual entry straight between two balance sheet accounts moves cash
      # without touching profit, and no named line covers it.
      journal(description: "Odd entry") do |e|
        post(e, code: 2500, name: "Some liability", type: "liability", credit: 90_00)
      end
      treasury_txn(kind: "income", amount_cents: 90_00)

      expect(bridge).not_to be_balanced
      expect(bridge.residual_cents).to eq(90_00)
    end
  end

  # ── The accrual split ───────────────────────────────────────────────
  #
  # An expense charged in one period and paid in another is exactly what the
  # voucher change introduced, and exactly what used to fall into the residual:
  # profit was down, cash had not moved, and no line named the difference.
  describe "expenses charged in one period and paid in another" do
    def line(key)
      bridge.lines.find { |l| l.key == key }
    end

    let(:category) do
      ExpenseCategory.create!(name: "Rent", category_type: "rent", position: 1, company: company)
    end

    # On account: no treasury, so nothing moved when it was recorded.
    def accrue_expense!(amount_cents:, date:)
      Expense.create!(expense_category: category, user: owner, company: company,
                      description: "Rent", amount_cents: amount_cents, expense_date: date)
    end

    it "names the charge in the period it was charged, and still closes" do
      accrue_expense!(amount_cents: 300_00, date: start_date + 2)

      expect(line(:unpaid_expenses).amount_cents).to eq(300_00)
      expect(bridge.residual_cents).to eq(0)
      expect(bridge).to be_balanced
    end

    it "names the payment in the period it was paid, and still closes" do
      expense = accrue_expense!(amount_cents: 300_00, date: start_date - 40)

      Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: owner,
        amount_cents: 300_00, voucher_date: start_date + 3,
        allocations: [{ settles: expense, amount_cents: 300_00 }]
      ).call

      # Cash left this period against a charge made in an earlier one.
      expect(line(:unpaid_expenses).amount_cents).to eq(-300_00)
      expect(bridge.residual_cents).to eq(0)
    end

    it "nets to nothing when the expense is paid as it is recorded" do
      Expense.create!(expense_category: category, user: owner, company: company,
                      treasury: cash, description: "Rent paid now",
                      amount_cents: 300_00, expense_date: start_date + 2)

      expect(bridge.lines.map(&:key)).not_to include(:unpaid_expenses)
      expect(bridge.residual_cents).to eq(0)
    end
  end

  describe "income earned in one period and collected in another" do
    def line(key)
      bridge.lines.find { |l| l.key == key }
    end

    let(:income_category) do
      IncomeCategory.create!(name: "Catering", category_type: "catering",
                             position: 1, company: company)
    end

    it "names the uncollected revenue, and still closes" do
      Income.create!(income_category: income_category, user: owner, company: company,
                     description: "Catering", amount_cents: 400_00,
                     income_date: start_date + 1)

      expect(line(:uncollected_income).amount_cents).to eq(-400_00)
      expect(bridge.residual_cents).to eq(0)
    end

    it "names the collection of revenue recognised earlier, and still closes" do
      income = Income.create!(income_category: income_category, user: owner, company: company,
                              description: "Catering", amount_cents: 400_00,
                              income_date: start_date - 40)

      Accounting::RecordVoucherService.new(
        direction: Voucher::RECEIPT, treasury: cash, user: owner,
        amount_cents: 400_00, voucher_date: start_date + 5,
        allocations: [{ settles: income, amount_cents: 400_00 }]
      ).call

      expect(line(:uncollected_income).amount_cents).to eq(400_00)
      expect(bridge.residual_cents).to eq(0)
    end
  end
end
