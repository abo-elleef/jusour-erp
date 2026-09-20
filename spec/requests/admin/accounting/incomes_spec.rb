# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::Incomes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }

  let!(:cash) do
    Treasury.create!(
      name: "Cash Drawer", treasury_type: "cash_drawer",
      balance_cents: 100_000, opening_balance_cents: 100_000, company: company
    )
  end

  let!(:category) do
    IncomeCategory.create!(name: "Catering", category_type: "catering", position: 1, company: company)
  end

  before { sign_in owner }

  def create_income(amount_cents: 20_000)
    Income.create!(
      income_category: category, amount_cents: amount_cents,
      income_date: Date.current, description: "Catering event",
      recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company
    )
  end

  def money(cents) = ApplicationController.helpers.format_amount(cents)

  describe "GET /admin/accounting/incomes" do
    # Every row listed is a live one now: undoing an income deletes it rather
    # than flagging it, so the total is simply the sum of what is there.
    it "shows the sum of incomes in the selected range" do
      create_income(amount_cents: 20_000)
      create_income(amount_cents: 12_500)

      get admin_accounting_incomes_path(start_date: Date.current.beginning_of_month, end_date: Date.current)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(money(32_500))
      expect(response.body).to include(I18n.t("accounting.incomes.stats_earned"))
    end

    it "drops a deleted income out of the total" do
      create_income(amount_cents: 20_000)
      gone = create_income(amount_cents: 40_000)

      delete admin_accounting_income_path(gone)
      get admin_accounting_incomes_path(start_date: Date.current.beginning_of_month, end_date: Date.current)

      expect(response.body).to include(money(20_000))
      expect(response.body).not_to include(money(60_000))
    end
  end

  # ── Index pagination ─────────────────────────────────────────────────────

  describe "GET /admin/accounting/incomes (pagination)" do
    it "paginates at 50 per page and preserves filters across pages" do
      51.times { create_income }

      get admin_accounting_incomes_path(start_date: "2000-01-01")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.shared.pagination", page: 1, pages: 2))
      expect(response.body).to include(I18n.t("accounting.shared.pagination_showing", from: 1, to: 50, count: 51))

      get admin_accounting_incomes_path(page: 2, category_id: category.id, start_date: "2000-01-01")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.shared.pagination", page: 2, pages: 2))
      # the category filter is carried into the prev-page link
      expect(response.body).to include("category_id=#{category.id}")
    end

    it "shows the result count even when there is only one page" do
      3.times { create_income }
      get admin_accounting_incomes_path(start_date: "2000-01-01")
      expect(response.body).to include(I18n.t("accounting.shared.pagination_showing", from: 1, to: 3, count: 3))
    end

    it "renders first, last, and a window of numbered page links" do
      # 8 pages of 50 = 400 records
      400.times { create_income }
      get admin_accounting_incomes_path(page: 5, start_date: "2000-01-01")
      expect(response).to have_http_status(:ok)

      body = response.body
      # window is current ± 2 (pages 3..7) plus first (1) and last (8)
      [1, 3, 4, 6, 7, 8].each do |n|
        expect(body).to include("page=#{n}&amp;start_date") # numbered link href present
      end
      # current page (5) is rendered as the highlighted, non-link current marker
      expect(body).to include('aria-current="page"')
      # a gap marker sits between first (1) and the window start (3)
      expect(body).to include("…")
    end
  end

  # ── Reversal ─────────────────────────────────────────────────────────────

  # Deleting used to be impossible by route, and the model deliberately kept the
  # journal entry when a record was destroyed by other means. Both are reversed,
  # and reversal itself is gone: a deleted income takes its ledger with it, so
  # the P&L stops reporting money against a row nobody can open.
  describe "DELETE /admin/accounting/incomes/:id" do
    it "deletes the income, its journal entry and the voucher that collected it" do
      income = create_income(amount_cents: 20_000)
      voucher = Voucher.sole
      expect(JournalEntry.for_source(income)).to exist
      expect(TreasuryTransaction.where(source_record: voucher)).to exist

      expect { delete admin_accounting_income_path(income) }
        .to change(Income, :count).by(-1)
        .and change { Voucher.active.count }.by(-1)

      expect(JournalEntry.where(source_record_type: "Income", source_record_id: income.id)).to be_empty
      expect(TreasuryTransaction.where(source_record_type: "Voucher", source_record_id: voucher.id)).to be_empty
    end

    it "restores the treasury balance" do
      income = create_income(amount_cents: 20_000)
      expect(cash.reload.balance_cents).to eq(120_000)

      delete admin_accounting_income_path(income)

      expect(cash.reload.balance_cents).to eq(100_000)
    end

    it "leaves no journal lines behind" do
      income = create_income
      entry_id = JournalEntry.for_source(income).first.id

      delete admin_accounting_income_path(income)

      expect(JournalEntryLine.where(journal_entry_id: entry_id)).to be_empty
    end

    it "records an audit entry carrying what was deleted" do
      income = create_income(amount_cents: 20_000)

      delete admin_accounting_income_path(income)

      audit = AuditLogEntry.find_by(action: "income.destroy", record_id: income.id)
      expect(audit).to be_present
      expect(audit.changes_snapshot["amount_cents"]).to eq(20_000)
      expect(audit.changes_snapshot["description"]).to eq("Catering event")
    end
  end
end
