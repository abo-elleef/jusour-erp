# frozen_string_literal: true

require "rails_helper"

# The treasury ledger can be read either flat (100 rows a page) or grouped by
# day. Grouped mode paginates a whole business week at a time — Saturday→Friday,
# per config.beginning_of_week — so the reader can step week by week and see
# what went in and out each day.
RSpec.describe "Treasury day grouping", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let!(:treasury) do
    Treasury.create!(name: "Main Cash", treasury_type: "cash_drawer",
      balance_cents: 0, opening_balance_cents: 0, company: company)
  end

  # A Saturday, so the week runs 2026-09-05 → 2026-09-11.
  let(:this_saturday) { Date.new(2026, 9, 5) }
  let(:last_saturday) { this_saturday - 1.week }

  def txn(amount_cents, on:, description: "row")
    TreasuryTransaction.create!(
      treasury: treasury, user: owner, amount_cents: amount_cents, kind: amount_cents.positive? ? "income" : "expense",
      description: description, occurred_on: on, balance_after_cents: 0, company: company
    )
  end

  before { Current.company = company }

  def money(cents) = ApplicationController.helpers.format_amount(cents)

  describe "week pagination" do
    before do
      sign_in owner
      txn(10_000, on: this_saturday, description: "this week in")
      txn(-4_000, on: this_saturday, description: "this week out")
      txn(7_000, on: last_saturday, description: "last week in")
    end

    let(:range) { { start_date: last_saturday.to_s, end_date: this_saturday + 6 } }

    it "defaults to the newest week in range and excludes earlier weeks" do
      get admin_accounting_treasury_path(treasury, group_by: "day", **range)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("this week in")
      expect(response.body).not_to include("last week in")
    end

    it "steps back a whole week" do
      get admin_accounting_treasury_path(treasury, group_by: "day", week: last_saturday.to_s, **range)

      expect(response.body).to include("last week in")
      expect(response.body).not_to include("this week in")
    end

    it "clamps a week outside the range back into it" do
      get admin_accounting_treasury_path(treasury, group_by: "day", week: (last_saturday - 10.weeks).to_s, **range)

      expect(response.body).to include("last week in")
    end

    it "shows each day's in and out totals" do
      get admin_accounting_treasury_path(treasury, group_by: "day", **range)

      expect(response.body).to include(money(10_000))
      expect(response.body).to include(money(4_000))
      # Net for the day: 10,000 in less 4,000 out.
      expect(response.body).to include(money(6_000))
      expect(response.body).to include(I18n.t("accounting.treasuries.day_net"))
    end

    it "offers only a step back when the range starts mid-history" do
      get admin_accounting_treasury_path(treasury, group_by: "day", **range)

      expect(response.body).to include("week=#{last_saturday.iso8601}")
      expect(response.body).not_to include("week=#{(this_saturday + 1.week).iso8601}")
    end
  end

  describe "flat mode" do
    before do
      sign_in owner
      txn(10_000, on: this_saturday, description: "this week in")
      txn(7_000, on: last_saturday, description: "last week in")
    end

    it "keeps the unpaginated-by-week list when grouping is off" do
      get admin_accounting_treasury_path(treasury, start_date: last_saturday.to_s, end_date: (this_saturday + 6).to_s)

      expect(response.body).to include("this week in")
      expect(response.body).to include("last week in")
      expect(response.body).not_to include(I18n.t("accounting.treasuries.day_net"))
    end
  end
end
