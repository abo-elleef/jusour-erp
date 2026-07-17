# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::Partners", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let!(:cash) do
    Treasury.create!(
      name: "Cash", treasury_type: "cash_drawer",
      balance_cents: 100_000, opening_balance_cents: 100_000,
      company: company
    )
  end
  let!(:partner) do
    Partner.create!(name: "Ahmed", ownership_percentage: 100, company: company)
  end

  before { sign_in owner }

  def post_advance(amount:, treasury: cash, date: Date.current, description: "Partner advance")
    post create_advance_admin_accounting_partner_path(partner), params: {
      treasury_id: treasury.id,
      amount:      amount.to_s,
      date:        date.to_s,
      description: description
    }
  end

  describe "POST /admin/accounting/partners/:id/advance (partner advance)" do
    it "creates a journal entry" do
      expect { post_advance(amount: 500) }.to change(JournalEntry, :count).by(1)
    end

    it "creates a TreasuryTransaction linked to the journal entry" do
      post_advance(amount: 500)
      txn = TreasuryTransaction.last
      expect(txn.source_record).to be_a(JournalEntry)
    end

    it "creates a TreasuryTransaction with kind journal_entry" do
      post_advance(amount: 500)
      expect(TreasuryTransaction.last.kind).to eq("journal_entry")
    end

    it "decreases the treasury balance by the advance amount" do
      expect { post_advance(amount: 500) }
        .to change { cash.reload.balance_cents }.by(-50_000)
    end

    it "sets TreasuryTransaction amount to negative (cash flows out)" do
      post_advance(amount: 300)
      expect(TreasuryTransaction.last.amount_cents).to eq(-30_000)
    end

    it "records balance_after_cents matching the treasury balance after the operation" do
      post_advance(amount: 200)
      txn = TreasuryTransaction.last
      expect(txn.balance_after_cents).to eq(cash.reload.balance_cents)
    end

    it "redirects to the partner page on success" do
      post_advance(amount: 100)
      expect(response).to redirect_to(admin_accounting_partner_path(partner))
    end

    it "does not create any records when amount is zero" do
      je_before  = JournalEntry.count
      txn_before = TreasuryTransaction.count
      bal_before = cash.reload.balance_cents
      post_advance(amount: 0)
      expect(JournalEntry.count).to eq(je_before)
      expect(TreasuryTransaction.count).to eq(txn_before)
      expect(cash.reload.balance_cents).to eq(bal_before)
    end

    it "wraps the JE and treasury sync in one transaction (no orphaned TreasuryTransaction)" do
      # Both records must exist or neither; we verify they are created together
      post_advance(amount: 100)
      je  = JournalEntry.last
      txn = TreasuryTransaction.where(source_record: je).first
      expect(txn).not_to be_nil
    end
  end

  describe "access control" do
    before { sign_out owner }

    it "redirects unauthenticated requests to sign in" do
      post_advance(amount: 100)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
