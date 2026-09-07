# frozen_string_literal: true

require "rails_helper"

# The reconciliation harness for C1: a full trading day pushed through the ledger,
# asserting that revenue is recognised once, tax becomes a liability, the float is a
# transfer rather than income, and the sales clearing account tells the truth about
# what has and hasn't been banked.
RSpec.describe "POS revenue reaches the ledger" do
  let(:company) { create(:company) }
  let(:user) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:business_date) { Date.current }

  let!(:drawer) do
    Treasury.create!(company: company, name: "Register 1", treasury_type: "cash_drawer",
      opening_balance_cents: 0, balance_cents: 0)
  end
  let!(:safe) do
    Treasury.create!(company: company, name: "Main Safe", treasury_type: "safe",
      opening_balance_cents: 100_000, balance_cents: 100_000)
  end

  before { Current.company = company }

  def ledger(code)
    lines = JournalEntryLine.joins(:journal_entry)
      .where(journal_entries: { company_id: company.id }, account_code: code)
    lines.sum(:debit_cents).to_i - lines.sum(:credit_cents).to_i
  end

  def create_order(subtotal:, tax: 0, discount: 0, tip: 0)
    Order.create!(company: company, user: user, location: location, order_type: "pickup",
      status: "completed", subtotal_cents: subtotal, discount_cents: discount,
      tax_cents: tax, tip_cents: tip, total_cents: subtotal - discount + tax + tip)
  end

  def post_day!
    Accounting::JournalEntryService.record_daily_sales!(
      location: location, business_date: business_date, user: user
    )
  end

  describe "the day's sales entry" do
    it "recognises revenue net of tax and books the tax as a liability" do
      create_order(subtotal: 100_000, tax: 14_000, discount: 10_000)
      post_day!

      expect(ledger(Accounting::JournalEntryService::SALES_REVENUE_CODE)).to eq(-90_000)
      expect(ledger(Accounting::JournalEntryService::TAX_PAYABLE_CODE)).to eq(-14_000)
      expect(ledger(Accounting::JournalEntryService::SALES_CLEARING_CODE)).to eq(104_000)
    end

    it "credits nothing to equity" do
      create_order(subtotal: 50_000)
      post_day!

      expect(ledger(Accounting::JournalEntryService::EQUITY_CODE)).to eq(0)
    end

    it "balances" do
      create_order(subtotal: 100_000, tax: 14_000, tip: 5_000)
      post_day!

      entry = JournalEntry.where(company: company).last
      expect(entry.lines.sum(:debit_cents))
        .to eq(entry.lines.sum(:credit_cents))
    end

    it "is idempotent — re-posting the same day replaces it" do
      create_order(subtotal: 100_000)
      post_day!
      expect { post_day! }.not_to change { ledger(Accounting::JournalEntryService::SALES_REVENUE_CODE) }
      expect(JournalEntry.where(company: company).count).to eq(1)
    end

    it "posts nothing for a day with no completed orders" do
      expect { post_day! }.not_to change(JournalEntry, :count)
    end

    it "ignores orders that were never completed" do
      create_order(subtotal: 100_000).update!(status: "cancelled")
      post_day!

      expect(JournalEntry.where(company: company).count).to eq(0)
    end
  end

  describe "the float" do
    it "moves between treasuries without touching revenue or equity" do
      session = CashDrawerSession.create!(company: company, user: user, treasury: drawer,
        float_source_treasury: safe, location: location, session_date: business_date,
        opening_float_cents: 10_000, status: "open")
      Accounting::TreasuryLedgerService.sync_drawer_open!(session)

      expect(drawer.reload.balance_cents).to eq(10_000)
      expect(safe.reload.balance_cents).to eq(90_000)
      expect(ledger(Accounting::JournalEntryService::EQUITY_CODE)).to eq(0)
      expect(ledger(Accounting::JournalEntryService::SALES_REVENUE_CODE)).to eq(0)
    end
  end

  describe "a full day, cash only" do
    it "clears to zero once the takings are banked" do
      create_order(subtotal: 40_000)

      session = CashDrawerSession.create!(company: company, user: user, treasury: drawer,
        float_source_treasury: safe, location: location, session_date: business_date,
        opening_float_cents: 10_000, status: "open")
      Accounting::TreasuryLedgerService.sync_drawer_open!(session)

      post_day!

      # Counted at close = float + the day's cash takings, nothing missing.
      session.update!(counted_cash_cents: 50_000, status: "reconciled")
      Accounting::TreasuryLedgerService.sync_drawer_reconcile!(session)

      expect(ledger(Accounting::JournalEntryService::SALES_CLEARING_CODE)).to eq(0)
      expect(ledger(Accounting::JournalEntryService::SALES_REVENUE_CODE)).to eq(-40_000)
      # The float came back out of the safe and the takings went in on top of it.
      expect(drawer.reload.balance_cents).to eq(50_000)
      expect(safe.reload.balance_cents).to eq(90_000)
    end

    it "leaves the shortfall visible in sales clearing when the drawer is short" do
      create_order(subtotal: 40_000)

      session = CashDrawerSession.create!(company: company, user: user, treasury: drawer,
        float_source_treasury: safe, location: location, session_date: business_date,
        opening_float_cents: 10_000, status: "open")
      Accounting::TreasuryLedgerService.sync_drawer_open!(session)
      post_day!

      # 100.00 short.
      session.update!(counted_cash_cents: 40_000, status: "reconciled")
      Accounting::TreasuryLedgerService.sync_drawer_reconcile!(session)

      expect(ledger(Accounting::JournalEntryService::SALES_CLEARING_CODE)).to eq(10_000)
    end
  end

  describe "card takings" do
    it "are recognised as revenue even though no drawer session ever sees them" do
      create_order(subtotal: 75_000)
      post_day!

      expect(ledger(Accounting::JournalEntryService::SALES_REVENUE_CODE)).to eq(-75_000)
      # Still unbanked: nothing has cleared it yet.
      expect(ledger(Accounting::JournalEntryService::SALES_CLEARING_CODE)).to eq(75_000)
    end
  end
end
