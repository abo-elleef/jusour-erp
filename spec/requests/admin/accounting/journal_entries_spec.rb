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

  describe "GET /admin/accounting/journal_entries" do
    # Three entries with deliberately opposed orderings: newest is smallest, so
    # a date sort and an amount sort cannot accidentally agree.
    let!(:small_recent) { entry_with(date: Date.current,          amount_cents: 100_00, number: "JE-S1") }
    let!(:large_old)    { entry_with(date: Date.current - 5.days, amount_cents: 900_00, number: "JE-S2") }
    let!(:middle)       { entry_with(date: Date.current - 2.days, amount_cents: 500_00, number: "JE-S3") }

    def entry_with(date:, amount_cents:, number:)
      je = JournalEntry.create!(company: company, created_by: owner, date: date,
                                description: "Entry #{number}", entry_number: number,
                                entry_type: "manual")
      je.lines.create!(account_code: 5027, account_name: "Rent", account_type: "expense",
                       debit_cents: amount_cents, credit_cents: 0)
      je.lines.create!(account_code: 1001, account_name: "Cash", account_type: "asset",
                       debit_cents: 0, credit_cents: amount_cents)
      je
    end

    def listed_numbers(body)
      body.scan(/JE-S\d/).uniq
    end

    def get_index(params = {})
      get admin_accounting_journal_entries_path(
        { start_date: Date.current - 30, end_date: Date.current }.merge(params)
      )
    end

    it "defaults to newest first" do
      get_index

      expect(response).to have_http_status(:ok)
      expect(listed_numbers(response.body)).to eq(%w[JE-S1 JE-S3 JE-S2])
    end

    it "sorts by date ascending" do
      get_index(sort: "date", dir: "asc")

      expect(listed_numbers(response.body)).to eq(%w[JE-S2 JE-S3 JE-S1])
    end

    it "sorts by debits, smallest first" do
      get_index(sort: "debits", dir: "asc")

      expect(listed_numbers(response.body)).to eq(%w[JE-S1 JE-S3 JE-S2])
    end

    it "sorts by debits, largest first" do
      get_index(sort: "debits", dir: "desc")

      expect(listed_numbers(response.body)).to eq(%w[JE-S2 JE-S3 JE-S1])
    end

    it "sorts by credits" do
      get_index(sort: "credits", dir: "asc")

      expect(listed_numbers(response.body)).to eq(%w[JE-S1 JE-S3 JE-S2])
    end

    it "ignores a sort column it does not know" do
      get_index(sort: "'; DROP TABLE journal_entries; --")

      expect(response).to have_http_status(:ok)
      expect(listed_numbers(response.body)).to eq(%w[JE-S1 JE-S3 JE-S2])
    end

    it "keeps the active filter when sorting" do
      get_index(entry_type: "manual", sort: "debits", dir: "desc")

      expect(listed_numbers(response.body)).to eq(%w[JE-S2 JE-S3 JE-S1])
      # The sort links carry the filter forward rather than dropping it.
      expect(response.body).to include("entry_type=manual")
    end

    it "sorts the CSV export the same way as the table" do
      get admin_accounting_journal_entries_path(
        start_date: Date.current - 30, end_date: Date.current,
        sort: "debits", dir: "desc", format: :csv
      )

      expect(response).to have_http_status(:ok)
      expect(listed_numbers(response.body)).to eq(%w[JE-S2 JE-S3 JE-S1])
    end

    it "swaps the table inside a turbo frame so sorting does not jump the page" do
      get_index

      expect(response.body).to include('id="journal_entries_table"')
    end
  end

  describe "GET /admin/accounting/journal_entries/new" do
    it "renders searchable account pickers" do
      get new_admin_accounting_journal_entry_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="searchable-select"')
      expect(response.body).to include("data-searchable-select-options")
      expect(response.body).to include(treasury_encoded(cash))
      expect(response.body).to include(treasury_encoded(bank))
    end
  end

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

end
