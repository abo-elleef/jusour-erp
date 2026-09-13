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

  def txn(treasury:, kind:, amount_cents:, occurred_on: Date.current, source_record: nil)
    TreasuryTransaction.create!(
      treasury: treasury, user: owner,
      kind: kind, amount_cents: amount_cents,
      description: kind, occurred_on: occurred_on, source_record: source_record,
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

    it "excludes internal kinds (transfer, drawer_open)" do
      txn(treasury: cash, kind: "transfer",    amount_cents: 5_000)
      txn(treasury: cash, kind: "drawer_open", amount_cents: 1_000)
      expect(service.operating.lines).to be_empty
    end

    # Not internal, despite sitting next to drawer_open: this leg is the cash the
    # customers actually paid during the session, banked once. drawer_open is the
    # wash — it records the safe leg and the drawer leg, and the pair nets to zero.
    it "counts drawer_reconcile as operating cash from customers" do
      txn(treasury: cash, kind: "drawer_reconcile", amount_cents: 7_000)
      expect(service.operating.total_cents).to eq(7_000)
    end

    it "excludes ap_invoice (non-cash accrual)" do
      txn(treasury: cash, kind: "ap_invoice", amount_cents: -2_000)
      expect(service.operating.lines).to be_empty
    end

    # Used to be excluded wholesale, on the grounds that financing reads loan and
    # partner flows from the journal. That held for those two accounts only, so
    # every reversal disappeared: the outflow stayed and the restoring entry did
    # not. Entries touching a financing account are still excluded, below.
    # The expense line answers "what did we pay out in expenses", so it is built
    # from Expense records alone. Cash arriving because an entry was written or
    # reversed is a different question and gets its own row.
    it "keeps journal_entry cash off the expense line" do
      txn(treasury: cash, kind: "expense",       amount_cents: -2_000)
      txn(treasury: cash, kind: "journal_entry", amount_cents: 500)

      lines = service.operating.lines
      expect(lines.find { |l| l.kind == "expense" }.amount_cents).to eq(-2_000)
      expect(lines.find { |l| l.kind == "journal_entry" }.amount_cents).to eq(500)
    end

    it "reports journal_entry cash even with no expense in the period" do
      txn(treasury: cash, kind: "journal_entry", amount_cents: -500)

      line = service.operating.lines.find { |l| l.kind == "journal_entry" }
      expect(line).to be_present
      expect(line.amount_cents).to eq(-500)
    end

    # A line whose drill-down does not add up to it is worse than no drill-down.
    it "backs each line with exactly the rows it was built from" do
      txn(treasury: cash, kind: "expense",       amount_cents: -2_000)
      txn(treasury: cash, kind: "journal_entry", amount_cents: 500)

      service.operating.lines.each do |line|
        expect(service.transactions_for_kind(line.kind).sum(:amount_cents)).to eq(line.amount_cents)
      end
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

  # Investing now reads the treasury ledger rather than the FixedAsset register.
  # The register booked the full price on the purchase date even when the machine was
  # bought on credit and no cash had moved — and once a purchase also needed an
  # Expense to reconcile the safe, the same machine appeared in investing AND
  # operating. These specs previously asserted that register behaviour.
  describe "#investing" do
    it "includes asset purchases paid in cash within the range" do
      txn(treasury: cash, kind: "fixed_asset_purchase", amount_cents: -50_000)

      expect(service.investing.total_cents).to eq(-50_000)
    end

    it "excludes cash movements outside the date range" do
      txn(treasury: cash, kind: "fixed_asset_purchase", amount_cents: -30_000,
          occurred_on: 2.years.ago.to_date)

      expect(service.investing.lines).to be_empty
    end

    it "counts installments on a credit purchase, since that is when cash moves" do
      txn(treasury: cash, kind: "fixed_asset_payment", amount_cents: -12_000)

      expect(service.investing.total_cents).to eq(-12_000)
    end

    it "groups by kind: purchases and installments as separate lines" do
      txn(treasury: cash, kind: "fixed_asset_purchase", amount_cents: -10_000)
      txn(treasury: cash, kind: "fixed_asset_payment", amount_cents: -4_000)

      expect(service.investing.lines.map(&:kind))
        .to contain_exactly("fixed_asset_purchase", "fixed_asset_payment")
      expect(service.investing.total_cents).to eq(-14_000)
    end

    it "ignores an asset recorded on credit until it is paid" do
      FixedAsset.create!(
        name: "Unpaid Oven", asset_type: "equipment", on_credit: true,
        purchase_date: Date.current, purchase_price_cents: 50_000,
        current_value_cents: 50_000, recorded_by: owner, company: company
      )

      expect(service.investing.lines).to be_empty
    end

    it "returns an empty section when no assets were purchased in range" do
      expect(service.investing.lines).to be_empty
      expect(service.investing.total_cents).to eq(0)
    end
  end

  # ── Financing ─────────────────────────────────────────────────────────

  # Financing reports cash that actually moved. Journal lines on a loan or
  # partner account say what an entry was about; they do not say whether money
  # changed hands, and the section used to trust them.
  describe "#financing" do
    # Mirrors the app: the entry is written, then sync_je_treasuries! records the
    # movement for whichever line carries a treasury.
    def financing_entry(account_code:, debit_cents: 0, credit_cents: 0, moved_cents: nil, date: Date.current)
      je = manual_je(date: date)
      je_line(journal_entry: je, account_code: account_code,
              debit_cents: debit_cents, credit_cents: credit_cents)
      if moved_cents
        txn(treasury: cash, kind: "journal_entry", amount_cents: moved_cents, occurred_on: date)
          .update!(source_record: je)
      end
      je
    end

    context "with loans" do
      let!(:loan) { Loan.create!(name: "Bank Loan", loan_type: "bank_loan", principal_cents: 100_000, company: company) }

      it "reports a drawdown from the cash that arrived" do
        financing_entry(account_code: loan.account_code, credit_cents: 20_000, moved_cents: 20_000)

        line = service.financing.lines.find { |l| l.kind == "loan_proceeds" }
        expect(line.amount_cents).to eq(20_000)
        expect(line.account_code).to eq(loan.account_code)
      end

      it "reports a repayment from the cash that left" do
        financing_entry(account_code: loan.account_code, debit_cents: 5_000, moved_cents: -5_000)

        line = service.financing.lines.find { |l| l.kind == "loan_repayment" }
        expect(line.amount_cents).to eq(-5_000)
      end

      # The bug this rewrite exists to kill: an entry debiting the loan and
      # crediting an expense account is not a repayment, because no cash left.
      it "ignores an entry on the loan account that moved no cash" do
        financing_entry(account_code: loan.account_code, debit_cents: 5_000, moved_cents: nil)

        expect(service.financing.lines).to be_empty
        expect(service.financing.total_cents).to eq(0)
        expect(service).to be_balanced
      end

      it "excludes movement outside the date range" do
        financing_entry(account_code: loan.account_code, credit_cents: 10_000,
                        moved_cents: 10_000, date: 2.years.ago.to_date)

        expect(service.financing.lines).to be_empty
      end

      it "splits a period with money moving both ways into two lines" do
        financing_entry(account_code: loan.account_code, credit_cents: 20_000, moved_cents: 20_000)
        financing_entry(account_code: loan.account_code, debit_cents: 8_000, moved_cents: -8_000)

        expect(service.financing.lines.map(&:kind)).to contain_exactly("loan_proceeds", "loan_repayment")
        expect(service.financing.total_cents).to eq(12_000)
      end
    end

    context "with partners" do
      let!(:partner) { Partner.create!(name: "Ahmed", ownership_percentage: 100, company: company) }

      it "reports a contribution from the cash that arrived" do
        financing_entry(account_code: partner.account_code, credit_cents: 15_000, moved_cents: 15_000)

        line = service.financing.lines.find { |l| l.kind == "capital_contribution" }
        expect(line.amount_cents).to eq(15_000)
      end

      it "reports a drawing from the cash that left" do
        financing_entry(account_code: partner.account_code, debit_cents: 8_000, moved_cents: -8_000)

        line = service.financing.lines.find { |l| l.kind == "partner_drawings" }
        expect(line.amount_cents).to eq(-8_000)
      end

      it "keeps the drawing out of operating, so the cash is counted once" do
        financing_entry(account_code: partner.account_code, debit_cents: 8_000, moved_cents: -8_000)

        expect(service.operating.lines.find { |l| l.kind == "journal_entry" }).to be_nil
        expect(service.net_change_cents).to eq(-8_000)
        expect(service).to be_balanced
      end
    end

    # Reproduces the pair of entries found in production (both described
    # "تيست"): one moved a pound of cash onto the loan, the other debited the
    # loan and credited an expense account without touching cash. The second was
    # being reported as a 1.00 repayment, which is where the statement's
    # unexplained 1.00 came from.
    it "reports only the pound that moved, not the one that did not" do
      loan = Loan.create!(name: "Test Loan", loan_type: "bank_loan",
                          principal_cents: 0, company: company)
      drawdown = manual_je
      je_line(journal_entry: drawdown, account_code: loan.account_code, credit_cents: 100)
      txn(treasury: cash, kind: "journal_entry", amount_cents: 100).update!(source_record: drawdown)

      paper = manual_je
      je_line(journal_entry: paper, account_code: loan.account_code, debit_cents: 100)
      je_line(journal_entry: paper, account_code: 5006, credit_cents: 100)

      expect(service.financing.lines.map(&:kind)).to eq(%w[loan_proceeds])
      expect(service.financing.total_cents).to eq(100)
      expect(service.unclassified_cents).to eq(0)
      expect(service).to be_balanced
    end

    it "returns an empty section when no financing cash moved" do
      expect(service.financing.lines).to be_empty
      expect(service.financing.total_cents).to eq(0)
    end
  end

  # ── Totals ────────────────────────────────────────────────────────────

  describe "#net_change_cents" do
    it "reports what the treasuries actually did" do
      txn(treasury: cash, kind: "income",  amount_cents: 10_000)
      txn(treasury: cash, kind: "expense", amount_cents: -3_000)
      txn(treasury: cash, kind: "fixed_asset_purchase", amount_cents: -2_000)

      expect(service.net_change_cents).to eq(10_000 - 3_000 - 2_000)
      expect(service.classified_change_cents).to eq(service.net_change_cents)
      expect(service).to be_balanced
    end

    it "counts movement the sections cannot classify, and says so" do
      txn(treasury: cash, kind: "income", amount_cents: 10_000)
      txn(treasury: cash, kind: "ap_invoice", amount_cents: 7_000)

      expect(service.classified_change_cents).to eq(10_000)
      expect(service.net_change_cents).to eq(17_000)
      expect(service.unclassified_cents).to eq(7_000)
      expect(service).not_to be_balanced
    end

    it "excludes supplier_ap movement" do
      ap = Treasury.create!(
        name: "AP", treasury_type: "supplier_ap",
        balance_cents: 0, opening_balance_cents: 0, company: company
      )
      txn(treasury: ap, kind: "ap_invoice", amount_cents: 40_000)

      expect(service.net_change_cents).to eq(0)
    end
  end

  # Balances are built from the ledger rather than from Treasury#balance_cents,
  # which is a live figure: reading it for a period that has already closed
  # reports the balance now, not the balance then.
  describe "#beginning_balance_cents and #ending_balance_cents" do
    it "opens with the float plus everything banked before the period" do
      txn(treasury: cash, kind: "income", amount_cents: 5_000, occurred_on: start_date - 3)
      txn(treasury: cash, kind: "income", amount_cents: 1_000)

      expect(service.beginning_balance_cents).to eq(5_000)
      expect(service.ending_balance_cents).to eq(5_000 + 1_000)
    end

    it "ignores movement after the period, which a live balance would include" do
      txn(treasury: cash, kind: "income", amount_cents: 1_000)
      txn(treasury: cash, kind: "income", amount_cents: 99_000, occurred_on: end_date + 5)

      expect(service.ending_balance_cents).to eq(1_000)
    end

    it "always reconciles: opening + change = ending" do
      txn(treasury: cash, kind: "income", amount_cents: 1_000)
      txn(treasury: cash, kind: "drawer_reconcile", amount_cents: 700)

      svc = service
      expect(svc.beginning_balance_cents + svc.net_change_cents).to eq(svc.ending_balance_cents)
    end

    it "excludes supplier_ap treasuries" do
      Treasury.create!(
        name: "AP", treasury_type: "supplier_ap",
        balance_cents: 99_000, opening_balance_cents: 99_000, company: company
      )

      expect(service.beginning_balance_cents).to eq(0)
    end
  end

  describe "journal entries that the financing section already reports" do
    it "are left out of operating, to avoid counting the same cash twice" do
      partner = Partner.create!(company: company, name: "Owner", ownership_percentage: 100)
      drawing = JournalEntry.create!(company: company, created_by: owner, date: Date.current,
                                     description: "Drawing", entry_number: "JE-CF-DBL")
      drawing.lines.create!(account_code: partner.account_code, account_name: "Owner",
                            account_type: "equity", debit_cents: 30_000, credit_cents: 0)
      txn(treasury: cash, kind: "journal_entry", amount_cents: -30_000, source_record: drawing)

      expect(service.financing.total_cents).to eq(-30_000)
      expect(service.operating.lines.find { |l| l.kind == "journal_entry" }).to be_nil
      expect(service.net_change_cents).to eq(-30_000)
      expect(service).to be_balanced
    end
  end
end
