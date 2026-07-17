# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::Loans", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let!(:cash) do
    Treasury.create!(
      name: "Cash", treasury_type: "cash_drawer",
      balance_cents: 200_000, opening_balance_cents: 200_000,
      company: company
    )
  end
  let!(:loan) do
    Loan.create!(
      name: "Bank Loan", loan_type: "bank_loan",
      principal_cents: 500_000, interest_rate: 5.0,
      company: company
    )
  end

  before { sign_in owner }

  # ── Disbursement ─────────────────────────────────────────────────────────────

  describe "POST /admin/accounting/loans/:id/disbursement (receive loan proceeds)" do
    def post_disbursement(amount:, treasury: cash, date: Date.current)
      post create_disbursement_admin_accounting_loan_path(loan), params: {
        treasury_id: treasury.id,
        amount:      amount.to_s,
        date:        date.to_s,
        description: "Loan disbursement"
      }
    end

    it "creates a journal entry" do
      expect { post_disbursement(amount: 1_000) }.to change(JournalEntry, :count).by(1)
    end

    it "creates a TreasuryTransaction with kind journal_entry" do
      post_disbursement(amount: 1_000)
      expect(TreasuryTransaction.last.kind).to eq("journal_entry")
    end

    it "increases the treasury balance (cash comes in)" do
      expect { post_disbursement(amount: 1_000) }
        .to change { cash.reload.balance_cents }.by(100_000)
    end

    it "sets TreasuryTransaction amount to positive" do
      post_disbursement(amount: 500)
      expect(TreasuryTransaction.last.amount_cents).to eq(50_000)
    end

    it "links TreasuryTransaction to the journal entry" do
      post_disbursement(amount: 200)
      expect(TreasuryTransaction.last.source_record).to be_a(JournalEntry)
    end

    it "records balance_after_cents matching the treasury balance after the operation" do
      post_disbursement(amount: 300)
      txn = TreasuryTransaction.last
      expect(txn.balance_after_cents).to eq(cash.reload.balance_cents)
    end

    it "redirects to the loan page on success" do
      post_disbursement(amount: 100)
      expect(response).to redirect_to(admin_accounting_loan_path(loan))
    end

    it "does not create records when amount is zero" do
      je_before  = JournalEntry.count
      txn_before = TreasuryTransaction.count
      post_disbursement(amount: 0)
      expect(JournalEntry.count).to eq(je_before)
      expect(TreasuryTransaction.count).to eq(txn_before)
    end
  end

  # ── Repayment ─────────────────────────────────────────────────────────────────

  describe "POST /admin/accounting/loans/:id/repayment (pay back principal)" do
    def post_repayment(amount:, treasury: cash, date: Date.current)
      post create_repayment_admin_accounting_loan_path(loan), params: {
        treasury_id: treasury.id,
        amount:      amount.to_s,
        date:        date.to_s,
        description: "Loan repayment"
      }
    end

    it "creates a journal entry" do
      expect { post_repayment(amount: 500) }.to change(JournalEntry, :count).by(1)
    end

    it "creates a TreasuryTransaction with kind journal_entry" do
      post_repayment(amount: 500)
      expect(TreasuryTransaction.last.kind).to eq("journal_entry")
    end

    it "decreases the treasury balance (cash goes out)" do
      expect { post_repayment(amount: 500) }
        .to change { cash.reload.balance_cents }.by(-50_000)
    end

    it "sets TreasuryTransaction amount to negative" do
      post_repayment(amount: 400)
      expect(TreasuryTransaction.last.amount_cents).to eq(-40_000)
    end

    it "links TreasuryTransaction to the journal entry" do
      post_repayment(amount: 100)
      expect(TreasuryTransaction.last.source_record).to be_a(JournalEntry)
    end

    it "records balance_after_cents matching the treasury balance after the operation" do
      post_repayment(amount: 200)
      txn = TreasuryTransaction.last
      expect(txn.balance_after_cents).to eq(cash.reload.balance_cents)
    end

    it "redirects to the loan page on success" do
      post_repayment(amount: 100)
      expect(response).to redirect_to(admin_accounting_loan_path(loan))
    end

    it "does not create records when amount is zero" do
      je_before  = JournalEntry.count
      txn_before = TreasuryTransaction.count
      post_repayment(amount: 0)
      expect(JournalEntry.count).to eq(je_before)
      expect(TreasuryTransaction.count).to eq(txn_before)
    end
  end

  # ── Interest ──────────────────────────────────────────────────────────────────

  describe "POST /admin/accounting/loans/:id/interest (pay interest)" do
    def post_interest(amount:, treasury: cash, date: Date.current)
      post create_interest_admin_accounting_loan_path(loan), params: {
        treasury_id: treasury.id,
        amount:      amount.to_s,
        date:        date.to_s,
        description: "Interest payment"
      }
    end

    it "creates a journal entry" do
      expect { post_interest(amount: 100) }.to change(JournalEntry, :count).by(1)
    end

    it "creates a TreasuryTransaction with kind journal_entry" do
      post_interest(amount: 100)
      expect(TreasuryTransaction.last.kind).to eq("journal_entry")
    end

    it "decreases the treasury balance (cash goes out)" do
      expect { post_interest(amount: 100) }
        .to change { cash.reload.balance_cents }.by(-10_000)
    end

    it "sets TreasuryTransaction amount to negative" do
      post_interest(amount: 50)
      expect(TreasuryTransaction.last.amount_cents).to eq(-5_000)
    end

    it "links TreasuryTransaction to the journal entry" do
      post_interest(amount: 75)
      expect(TreasuryTransaction.last.source_record).to be_a(JournalEntry)
    end

    it "records balance_after_cents matching the treasury balance after the operation" do
      post_interest(amount: 25)
      txn = TreasuryTransaction.last
      expect(txn.balance_after_cents).to eq(cash.reload.balance_cents)
    end

    it "redirects to the loan page on success" do
      post_interest(amount: 50)
      expect(response).to redirect_to(admin_accounting_loan_path(loan))
    end

    it "does not create records when amount is zero" do
      je_before  = JournalEntry.count
      txn_before = TreasuryTransaction.count
      post_interest(amount: 0)
      expect(JournalEntry.count).to eq(je_before)
      expect(TreasuryTransaction.count).to eq(txn_before)
    end
  end

  # ── Access control ────────────────────────────────────────────────────────────

  describe "access control" do
    before { sign_out owner }

    it "redirects unauthenticated disbursement requests to sign in" do
      post create_disbursement_admin_accounting_loan_path(loan), params: {
        treasury_id: cash.id, amount: "100", date: Date.current.to_s
      }
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
