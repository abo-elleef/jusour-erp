# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::JournalEntries", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }

  let!(:cash) do
    Treasury.create!(
      name: "Cash Drawer",
      treasury_type: "cash_drawer",
      balance_cents: 50_000,
      opening_balance_cents: 50_000,
      company: company
    )
  end
  let!(:bank) do
    Treasury.create!(
      name: "Bank Account",
      treasury_type: "bank",
      balance_cents: 100_000,
      opening_balance_cents: 100_000,
      company: company
    )
  end

  before { sign_in owner }

  def treasury_encoded(treasury)
    "treasury|#{treasury.id}|#{treasury.name}|asset"
  end

  def post_je(debit_treasury:, credit_treasury:, amount_dollars:, description: "Test transfer")
    post admin_accounting_journal_entries_path, params: {
      journal_entry: {
        date: Date.current.to_s,
        description: description,
        lines_attributes: {
          "0" => {
            account_encoded: treasury_encoded(debit_treasury),
            debit_pounds:    amount_dollars.to_s,
            credit_pounds:   "0"
          },
          "1" => {
            account_encoded: treasury_encoded(credit_treasury),
            debit_pounds:    "0",
            credit_pounds:   amount_dollars.to_s
          }
        }
      }
    }
  end

  describe "POST /admin/accounting/journal_entries (manual JE)" do
    it "creates the journal entry record" do
      expect { post_je(debit_treasury: cash, credit_treasury: bank, amount_dollars: 100) }
        .to change(JournalEntry, :count).by(1)

      entry = JournalEntry.last
      expect(entry.entry_type).to eq("manual")
      expect(entry.lines.count).to eq(2)
    end

    it "moves the balance from the credit treasury to the debit treasury" do
      post_je(debit_treasury: cash, credit_treasury: bank, amount_dollars: 200)

      # cash is debited → balance increases by 200
      expect(cash.reload.balance_cents).to eq(50_000 + 20_000)
      # bank is credited → balance decreases by 200
      expect(bank.reload.balance_cents).to eq(100_000 - 20_000)
    end

    it "creates a TreasuryTransaction of kind 'journal_entry' for each treasury line" do
      post_je(debit_treasury: cash, credit_treasury: bank, amount_dollars: 50)

      je = JournalEntry.last
      txns = TreasuryTransaction.where(source_record: je)

      expect(txns.count).to eq(2)
      expect(txns.pluck(:kind).uniq).to eq(["journal_entry"])

      cash_txn = txns.find { |t| t.treasury_id == cash.id }
      bank_txn = txns.find { |t| t.treasury_id == bank.id }

      expect(cash_txn.amount_cents).to eq(5_000)   # debit  → positive
      expect(bank_txn.amount_cents).to eq(-5_000)  # credit → negative
    end

    it "records balance_after_cents at the time of the transaction" do
      post_je(debit_treasury: cash, credit_treasury: bank, amount_dollars: 100)

      je = JournalEntry.last
      cash_txn = TreasuryTransaction.find_by(source_record: je, treasury: cash)
      bank_txn = TreasuryTransaction.find_by(source_record: je, treasury: bank)

      expect(cash_txn.balance_after_cents).to eq(cash.reload.balance_cents)
      expect(bank_txn.balance_after_cents).to eq(bank.reload.balance_cents)
    end

    it "rolls back both the JE and treasury changes if something raises" do
      allow(Treasury).to receive(:lock).and_raise(ActiveRecord::RecordInvalid)

      expect { post_je(debit_treasury: cash, credit_treasury: bank, amount_dollars: 100) }
        .not_to change(JournalEntry, :count)

      expect(cash.reload.balance_cents).to eq(50_000)
      expect(bank.reload.balance_cents).to eq(100_000)
    end

    context "when the JE is unbalanced" do
      it "does not save the entry or change treasuries" do
        expect do
          post admin_accounting_journal_entries_path, params: {
            journal_entry: {
              date: Date.current.to_s,
              description: "Unbalanced",
              lines_attributes: {
                "0" => {
                  account_encoded: treasury_encoded(cash),
                  debit_pounds: "100",
                  credit_pounds: "0"
                },
                "1" => {
                  account_encoded: treasury_encoded(bank),
                  debit_pounds: "0",
                  credit_pounds: "50"
                }
              }
            }
          }
        end.not_to change(JournalEntry, :count)

        expect(cash.reload.balance_cents).to eq(50_000)
        expect(bank.reload.balance_cents).to eq(100_000)
      end
    end
  end

  describe "DELETE /admin/accounting/journal_entries/:id" do
    def create_manual_je(amount_cents: 10_000)
      post_je(debit_treasury: cash, credit_treasury: bank, amount_dollars: amount_cents / 100.0)
      JournalEntry.last
    end

    it "destroys the manual journal entry" do
      je = create_manual_je
      expect { delete admin_accounting_journal_entry_path(je) }
        .to change(JournalEntry, :count).by(-1)
    end

    it "reverses the treasury balances" do
      je = create_manual_je(amount_cents: 5_000)
      cash_before = cash.reload.balance_cents
      bank_before = bank.reload.balance_cents

      delete admin_accounting_journal_entry_path(je)

      expect(cash.reload.balance_cents).to eq(cash_before - 5_000)
      expect(bank.reload.balance_cents).to eq(bank_before + 5_000)
    end

    it "removes the associated TreasuryTransactions" do
      je = create_manual_je
      expect { delete admin_accounting_journal_entry_path(je) }
        .to change { TreasuryTransaction.where(source_record_type: "JournalEntry", source_record_id: je.id).count }.to(0)
    end

    it "redirects to the index with a notice" do
      je = create_manual_je
      delete admin_accounting_journal_entry_path(je)
      expect(response).to redirect_to(admin_accounting_journal_entries_path)
    end

    context "when trying to delete an auto-generated entry" do
      let!(:auto_je) do
        JournalEntry.create!(
          company: company,
          created_by: owner,
          entry_number: JournalEntry.next_entry_number(company.id),
          date: Date.current,
          description: "System entry",
          entry_type: "auto"
        )
      end

      it "redirects back with an alert and does not destroy the entry" do
        expect { delete admin_accounting_journal_entry_path(auto_je) }
          .not_to change(JournalEntry, :count)

        expect(response).to redirect_to(admin_accounting_journal_entry_path(auto_je))
      end
    end
  end
end
