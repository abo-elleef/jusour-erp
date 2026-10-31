# frozen_string_literal: true

require "rails_helper"

# The staff member page is a shell plus one lazily-loaded tab frame, and the
# employee's statement of account is a tab of its own with a printable twin.
RSpec.describe "Staff member page tabs and statement of account", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) { create(:user, company: company, role: "cashier", name: "Mona", monthly_salary_cents: 300_000) }
  let(:treasury) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 10_000_000, balance_cents: 10_000_000)
  end

  before do
    Current.company = company
    sign_in owner
  end

  def voucher(direction, cents, on:)
    Current.company = company # a request in between resets it
    Accounting::RecordVoucherService.new(direction: direction, treasury: treasury, user: owner,
                                         amount_cents: cents, voucher_date: on,
                                         party_type: "User", party_id: staff.id).call
  end

  describe "the shell" do
    it "renders the header and stats with an empty, lazily-loading tab frame" do
      voucher(Voucher::PAYMENT, 20_000, on: Date.current)

      get admin_user_path(staff)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mona", 'id="user_stats"', I18n.t("staff.wages_ledger.they_owe"))
      expect(response.body).to match(/<turbo-frame[^>]*id="user_tab"[^>]*src="[^"]*#{staff.id}/)
      expect(response.body).to include(I18n.t("staff.show.tabs.loading"))
      expect(response.body).not_to include(I18n.t("staff.show.account_details"))
    end

    it "keeps the requested tab in the frame src so a reload lands on it" do
      get admin_user_path(staff, tab: "statement")

      expect(response.body).to include("tab=statement")
    end
  end

  describe "tab frames" do
    it "opens on the overview when no tab is asked for" do
      get admin_user_path(staff), headers: { "Turbo-Frame" => "user_tab" }

      expect(response.body).to include(I18n.t("staff.show.account_details"))
      expect(response.body).to match(/<a[^>]*aria-current="page"[^>]*>#{I18n.t("staff.show.tabs.overview")}</)
    end

    it "falls back to the overview on an unknown tab" do
      get_user_tab(staff, "nope")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("staff.show.account_details"))
    end

    it "opens payroll for links that carry a payroll month but no tab" do
      get admin_user_path(staff, payroll_month: "2026-04"), headers: { "Turbo-Frame" => "user_tab" }

      expect(response.body).to include('value="2026-04"')
      expect(response.body).to match(/<a[^>]*aria-current="page"[^>]*>#{I18n.t("staff.show.tabs.payroll")}</)
    end

    it "refreshes the balance card and shows the flash after a payroll action" do
      post admin_user_payroll_adjustments_path(staff), params: {
        payroll_adjustment: { kind: "bonus", unit_type: "fixed", amount_pounds: "100",
                              payroll_month: "2026-04-01", happened_at: "2026-04-10" }
      }
      expect(response).to redirect_to(admin_user_path(staff, payroll_month: "2026-04-01"))

      get admin_user_path(staff, payroll_month: "2026-04-01"), headers: { "Turbo-Frame" => "user_tab" }

      expect(response.body).to include('<turbo-stream action="replace" target="user_stats">')
      expect(response.body).to include('<turbo-stream action="append" target="toast-container">')
      expect(response.body).to include(I18n.t("flash.payroll_adjustment.created"))
    end

    it "lists the change history" do
      staff.update!(name: "Mona Two")

      get_user_tab(staff, "history")

      expect(response.body).to include(I18n.t("accounting.audit_history.title"), "Mona Two")
    end
  end

  describe "statement of account" do
    it "runs oldest first from the opening balance to the account balance" do
      old = voucher(Voucher::PAYMENT, 1_000, on: Date.new(2026, 1, 5))
      first = voucher(Voucher::PAYMENT, 2_000, on: Date.new(2026, 3, 5))
      second = voucher(Voucher::RECEIPT, 500, on: Date.new(2026, 3, 20))

      get_user_tab(staff, "statement", start_date: "2026-03-01", end_date: "2026-03-31")

      body = response.body
      expect(body).not_to include(old.number)
      expect(body.index(first.number)).to be < body.index(second.number)
      expect(body).to include(admin_accounting_voucher_path(first))
      expect(body).to include("−#{ApplicationController.helpers.format_amount(1_000)}") # opening: they owe 10
      expect(body).to include("−#{ApplicationController.helpers.format_amount(2_500)}") # closing: they owe 25
      expect(staff.staff_balance_cents(as_of: Date.new(2026, 3, 31))).to eq(-2_500)
      expect(body).to include(CGI.escapeHTML(statement_admin_user_path(staff, start_date: "2026-03-01", end_date: "2026-03-31")))
    end

    it "defaults to the year so far and says so when it is empty" do
      travel_to Date.new(2026, 6, 15) do
        get_user_tab(staff, "statement")

        expect(response.body).to include('value="2026-01-01"', 'value="2026-06-15"')
        expect(response.body).to include(I18n.t("staff.wages_ledger.no_movements_in_range"))
      end
    end

    it "renders the printable page for the same range and swaps a reversed one" do
      paid = voucher(Voucher::PAYMENT, 2_000, on: Date.new(2026, 3, 5))

      get statement_admin_user_path(staff, start_date: "2026-03-31", end_date: "2026-03-01")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("staff.statement.title", name: "Mona"))
      expect(response.body).to include(paid.number, "window.print()")
    end
  end
end
