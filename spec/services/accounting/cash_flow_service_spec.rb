# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::CashFlowService do
  let(:company)  { Current.company }
  let(:owner)    { create(:user, :owner, company: company) }

  let!(:cash) do
    Treasury.create!(
      name: "Cash", treasury_type: "cash_drawer",
      balance_cents: 30_000, opening_balance_cents: 0, company: company
    )
  end
  let!(:bank) do
    Treasury.create!(
      name: "Bank", treasury_type: "bank",
      balance_cents: 20_000, opening_balance_cents: 0, company: company
    )
  end

  let(:start_date) { Date.current.beginning_of_year }
  let(:end_date)   { Date.current }

  def service
    described_class.new(start_date: start_date, end_date: end_date)
  end

  def txn(treasury:, kind:, amount_cents:, occurred_on: Date.current)
    TreasuryTransaction.create!(
      treasury: treasury, user: owner,
      kind: kind, amount_cents: amount_cents,
      description: kind, occurred_on: occurred_on,
      balance_after_cents: treasury.balance_cents
    )
  end

  def je_line(journal_entry:, account_code:, debit_cents: 0, credit_cents: 0)
    JournalEntryLine.create!(
      journal_entry: journal_entry,
      account_code: account_code, account_name: "Test",
      account_type: "liability", debit_cents: debit_cents, credit_cents: credit_cents
    )
  end

  def manual_je(date: Date.current)
    JournalEntry.create!(
      company: company, created_by: owner,
      entry_number: JournalEntry.next_entry_number(company.id),
      date: date, description: "Test JE", entry_type: "manual"
    )
  end

  # ── Operating ─────────────────────────────────────────────────────────

  describe "#operating" do
    it "sums income kind transactions as positive cash inflow" do
      txn(treasury: cash, kind: "income", amount_cents: 5_000)
      expect(service.operating.total_cents).to eq(5_000)
    end

    it "sums expense kind transactions as negative cash outflow" do
      txn(treasury: cash, kind: "expense", amount_cents: -3_000)
      expect(service.operating.total_cents).to eq(-3_000)
    end

    it "groups all operating kinds and sums correctly" do
      txn(treasury: cash, kind: "income",           amount_cents: 10_000)
      txn(treasury: cash, kind: "expense",          amount_cents: -4_000)
      txn(treasury: cash, kind: "payroll_salary",   amount_cents: -2_000)
      txn(treasury: cash, kind: "ap_payment",       amount_cents: -1_000)
      expect(service.operating.total_cents).to eq(3_000)
    end

    it "excludes internal kinds (transfer, drawer_open, drawer_reconcile)" do
      txn(treasury: cash, kind: "transfer",          amount_cents: 5_000)
      txn(treasury: cash, kind: "drawer_open",       amount_cents: 1_000)
      txn(treasury: cash, kind: "drawer_reconcile",  amount_cents: -500)
      expect(service.operating.lines).to be_empty
    end

    it "excludes ap_invoice (non-cash accrual)" do
      txn(treasury: cash, kind: "ap_invoice", amount_cents: -2_000)
      expect(service.operating.lines).to be_empty
    end

    it "excludes journal_entry kind (captured in financing via JELs)" do
      txn(treasury: cash, kind: "journal_entry", amount_cents: -500)
      expect(service.operating.lines).to be_empty
    end

    it "excludes supplier_ap treasury transactions" do
      ap_treasury = Treasury.create!(
        name: "Supplier AP", treasury_type: "supplier_ap",
        balance_cents: 0, opening_balance_cents: 0, company: company
      )
      txn(treasury: ap_treasury, kind: "income", amount_cents: 5_000)
      expect(service.operating.lines).to be_empty
    end

    it "respects the date range" do
      txn(treasury: cash, kind: "income", amount_cents: 8_000, occurred_on: 1.year.ago.to_date)
      expect(service.operating.lines).to be_empty
    end

    it "produces one line per kind with a translated label" do
      txn(treasury: cash, kind: "income",  amount_cents: 5_000)
      txn(treasury: cash, kind: "expense", amount_cents: -2_000)
      lines = service.operating.lines
      expect(lines.map(&:kind)).to contain_exactly("income", "expense")
    end
  end

  # ── Investing ─────────────────────────────────────────────────────────

  describe "#investing" do
    it "includes fixed asset purchases within the date range as outflows" do
      FixedAsset.create!(
        name: "Oven", asset_type: "equipment",
        purchase_date: Date.current, purchase_price_cents: 50_000,
        current_value_cents: 50_000, recorded_by: owner, company: company
      )
      expect(service.investing.total_cents).to eq(-50_000)
    end

    it "excludes fixed assets purchased outside the date range" do
      FixedAsset.create!(
        name: "Old Oven", asset_type: "equipment",
        purchase_date: 2.years.ago.to_date, purchase_price_cents: 30_000,
        current_value_cents: 20_000, recorded_by: owner, company: company
      )
      expect(service.investing.lines).to be_empty
    end

    it "shows each asset as a separate line" do
      2.times do |i|
        FixedAsset.create!(
          name: "Asset #{i}", asset_type: "equipment",
          purchase_date: Date.current, purchase_price_cents: 10_000,
          current_value_cents: 10_000, recorded_by: owner, company: company
        )
      end
      expect(service.investing.lines.size).to eq(2)
    end

    it "returns an empty section when no assets were purchased in range" do
      expect(service.investing.lines).to be_empty
      expect(service.investing.total_cents).to eq(0)
    end
  end

  # ── Financing ─────────────────────────────────────────────────────────

  describe "#financing" do
    context "with loans" do
      let!(:loan) { Loan.create!(name: "Bank Loan", loan_type: "bank_loan", principal_cents: 100_000, company: company) }

      it "treats JEL credits on the loan account as loan proceeds (inflow)" do
        je = manual_je
        je_line(journal_entry: je, account_code: loan.account_code, credit_cents: 20_000)
        line = service.financing.lines.find { |l| l.kind == "loan_proceeds" }
        expect(line).not_to be_nil
        expect(line.amount_cents).to eq(20_000)
      end

      it "treats JEL debits on the loan account as repayments (outflow)" do
        je = manual_je
        je_line(journal_entry: je, account_code: loan.account_code, debit_cents: 5_000)
        line = service.financing.lines.find { |l| l.kind == "loan_repayment" }
        expect(line).not_to be_nil
        expect(line.amount_cents).to eq(-5_000)
      end

      it "excludes JELs outside the date range" do
        je = manual_je(date: 2.years.ago.to_date)
        je_line(journal_entry: je, account_code: loan.account_code, credit_cents: 10_000)
        expect(service.financing.lines).to be_empty
      end
    end

    context "with partners" do
      let!(:partner) { Partner.create!(name: "Ahmed", ownership_percentage: 100, company: company) }

      it "treats JEL credits on partner account as capital contribution (inflow)" do
        je = manual_je
        je_line(journal_entry: je, account_code: partner.account_code, credit_cents: 15_000)
        line = service.financing.lines.find { |l| l.kind == "capital_contribution" }
        expect(line).not_to be_nil
        expect(line.amount_cents).to eq(15_000)
      end

      it "treats JEL debits on partner account as drawings (outflow)" do
        je = manual_je
        je_line(journal_entry: je, account_code: partner.account_code, debit_cents: 8_000)
        line = service.financing.lines.find { |l| l.kind == "partner_drawings" }
        expect(line).not_to be_nil
        expect(line.amount_cents).to eq(-8_000)
      end
    end

    it "returns an empty section when there are no loans or partner JELs" do
      expect(service.financing.lines).to be_empty
      expect(service.financing.total_cents).to eq(0)
    end
  end

  # ── Totals ────────────────────────────────────────────────────────────

  describe "#net_change_cents" do
    it "sums operating + investing + financing" do
      txn(treasury: cash, kind: "income",  amount_cents: 10_000)
      txn(treasury: cash, kind: "expense", amount_cents: -3_000)
      FixedAsset.create!(
        name: "Mixer", asset_type: "equipment",
        purchase_date: Date.current, purchase_price_cents: 2_000,
        current_value_cents: 2_000, recorded_by: owner, company: company
      )
      expect(service.net_change_cents).to eq(10_000 - 3_000 - 2_000)
    end
  end

  describe "#ending_balance_cents" do
    it "sums all active non-AP treasury balances" do
      expect(service.ending_balance_cents).to eq(30_000 + 20_000)
    end

    it "excludes supplier_ap treasuries" do
      Treasury.create!(
        name: "AP", treasury_type: "supplier_ap",
        balance_cents: 99_000, opening_balance_cents: 0, company: company
      )
      expect(service.ending_balance_cents).to eq(30_000 + 20_000)
    end
  end

  describe "#beginning_balance_cents" do
    it "equals ending_balance minus net_change" do
      txn(treasury: cash, kind: "income", amount_cents: 5_000)
      svc = service
      expect(svc.beginning_balance_cents).to eq(svc.ending_balance_cents - svc.net_change_cents)
    end
  end
end
