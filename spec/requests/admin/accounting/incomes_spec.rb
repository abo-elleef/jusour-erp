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

  def post_reverse(income)
    post reverse_admin_accounting_income_path(income)
  end

  def money(cents) = ApplicationController.helpers.format_amount(cents)

  describe "GET /admin/accounting/incomes" do
    it "shows the sum of active incomes in the selected range" do
      create_income(amount_cents: 20_000)
      create_income(amount_cents: 12_500)
      reversed = create_income(amount_cents: 40_000)
      post_reverse(reversed)

      get admin_accounting_incomes_path(start_date: Date.current.beginning_of_month, end_date: Date.current)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(money(32_500))
      expect(response.body).to include(I18n.t("accounting.incomes.stats_earned"))
      expect(response.body).not_to include(money(72_500))
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

  describe "POST /admin/accounting/incomes/:id/reverse" do
    it "preserves the original journal entry (does not delete it)" do
      income = create_income
      je = JournalEntry.for_source(income).first
      post_reverse(income)
      expect(JournalEntry.exists?(je.id)).to be true
    end

    it "creates a new reversal journal entry" do
      income = create_income
      expect { post_reverse(income) }.to change(JournalEntry, :count).by(1)
      reversal = JournalEntry.last
      expect(reversal.entry_type).to eq("reversal")
    end

    it "reversal entry flips debit/credit lines" do
      income = create_income(amount_cents: 10_000)
      je = JournalEntry.for_source(income).first
      post_reverse(income)
      reversal = JournalEntry.last

      je.lines.each do |original_line|
        rev_line = reversal.lines.find { |l| l.account_code == original_line.account_code }
        expect(rev_line.debit_cents).to eq(original_line.credit_cents)
        expect(rev_line.credit_cents).to eq(original_line.debit_cents)
      end
    end

    it "cancels the treasury balance effect (net zero after reversal)" do
      income = create_income(amount_cents: 5_000)
      balance_after_income = cash.reload.balance_cents
      post_reverse(income)
      expect(cash.reload.balance_cents).to eq(balance_after_income - 5_000)
    end

    it "creates TreasuryTransactions for the reversal entry" do
      income = create_income
      post_reverse(income)
      reversal = JournalEntry.last
      txns = TreasuryTransaction.where(source_record: reversal)
      expect(txns.count).to be >= 1
    end

    it "stamps reversed_at on the income" do
      income = create_income
      expect { post_reverse(income) }
        .to change { income.reload.reversed_at }.from(nil)
    end

    it "redirects to incomes index with a notice" do
      income = create_income
      post_reverse(income)
      expect(response).to redirect_to(admin_accounting_incomes_path)
      expect(flash[:notice]).to be_present
    end

    it "cannot reverse an already-reversed income" do
      income = create_income
      post_reverse(income)
      je_count_before = JournalEntry.count
      post_reverse(income)
      expect(JournalEntry.count).to eq(je_count_before)
      expect(response).to redirect_to(admin_accounting_incomes_path)
      expect(flash[:alert]).to be_present
    end

    it "redirects with alert if no journal entry exists" do
      income = create_income
      JournalEntry.for_source(income).destroy_all
      post_reverse(income)
      expect(flash[:alert]).to be_present
    end
  end

  # ── Edit/Update blocked for reversed incomes ──────────────────────────────

  describe "GET /admin/accounting/incomes/:id/edit (reversed)" do
    it "redirects with alert instead of showing the form" do
      income = create_income
      post_reverse(income)
      get edit_admin_accounting_income_path(income)
      expect(response).to redirect_to(admin_accounting_incomes_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "PATCH /admin/accounting/incomes/:id (reversed)" do
    it "redirects with alert and does not update the record" do
      income = create_income(amount_cents: 20_000)
      post_reverse(income)
      patch admin_accounting_income_path(income), params: {
        income: { amount_pounds: "999" }
      }
      expect(income.reload.amount_cents).to eq(20_000)
      expect(response).to redirect_to(admin_accounting_incomes_path)
      expect(flash[:alert]).to be_present
    end

    it "does not trigger JE recreation (no FK violation, no new JE)" do
      income = create_income
      post_reverse(income)
      je_count_before = JournalEntry.count
      patch admin_accounting_income_path(income), params: {
        income: { amount_pounds: "999" }
      }
      expect(JournalEntry.count).to eq(je_count_before)
    end
  end

  # ── Model validation ─────────────────────────────────────────────────────

  describe "Income model — immutable_once_reversed" do
    it "prevents update via model when reversed_at is set" do
      income = create_income
      income.update_column(:reversed_at, Time.current)
      result = income.update(amount_cents: 99_999)
      expect(result).to be false
      expect(income.errors[:base]).to be_present
      expect(income.reload.amount_cents).not_to eq(99_999)
    end

    it "allows update_column to bypass the validation (needed internally)" do
      income = create_income
      expect { income.update_column(:reversed_at, Time.current) }.not_to raise_error
    end
  end
end
