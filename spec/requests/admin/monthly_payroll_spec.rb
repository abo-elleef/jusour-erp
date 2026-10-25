# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::MonthlyPayroll", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before { Current.company = company }

  describe "GET /admin/accounting/monthly_payroll" do
    before { sign_in owner }

    it "renders the monthly payroll page" do
      create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)

      get admin_accounting_monthly_payroll_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.monthly_payroll.title"))
    end

    it "defaults to the previous month through the 5th of the new month" do
      travel_to Date.new(2026, 8, 1) do
        get admin_accounting_monthly_payroll_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('value="2026-07"')
      end
    end

    it "defaults to the current month from the 6th onward" do
      travel_to Date.new(2026, 8, 6) do
        get admin_accounting_monthly_payroll_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('value="2026-08"')
      end
    end

    it "renders staff salary portal links for the selected month" do
      staff = create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)

      get admin_accounting_monthly_payroll_path, params: { payroll_month: "2026-07" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.monthly_payroll.salary_link"))
      expect(response.body).to include(
        staff_payroll_url(token: staff.payroll_access_token, payroll_month: "2026-07")
      )
    end

    it "shows base salary and attendance pay side by side" do
      create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)

      get admin_accounting_monthly_payroll_path, params: { payroll_month: "2026-07" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.monthly_payroll.base_salary"))
      expect(response.body).to include(I18n.t("accounting.monthly_payroll.attendance_pay"))
    end

    it "filters staff by location" do
      downtown = create(:location, company: company, name: "Downtown")
      uptown = create(:location, company: company, name: "Uptown")
      branch_staff = create(:user, company: company, name: "Branch Cashier", role: "cashier",
                            monthly_salary_cents: 300_000, all_locations: false)
      branch_staff.locations = [downtown]
      other_staff = create(:user, company: company, name: "Other Branch", role: "cashier",
                           monthly_salary_cents: 300_000, all_locations: false)
      other_staff.locations = [uptown]

      get admin_accounting_monthly_payroll_path,
        params: { payroll_month: Date.current.strftime("%Y-%m"), location_id: downtown.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(%r{font-medium w-48">\s*<a [^>]*>Branch Cashier</a>\s*</td>})
      expect(response.body).not_to match(%r{font-medium w-48">\s*<a [^>]*>Other Branch</a>})
    end

    it "sorts rows by net pay descending" do
      create(:user, company: company, name: "Lower Paid", role: "cashier", monthly_salary_cents: 100_000)
      create(:user, company: company, name: "Higher Paid", role: "kitchen", monthly_salary_cents: 400_000)

      get admin_accounting_monthly_payroll_path, params: { sort: "net_pay_cents", direction: "desc" }

      expect(response).to have_http_status(:ok)
      expect(response.body.index("Higher Paid")).to be < response.body.index("Lower Paid")
    end

    it "shows what to pay this month, after the advance deduction" do
      payroll_month = Date.current.beginning_of_month
      staff = create(:user, company: company, name: "Advance Taker", role: "cashier",
                     monthly_salary_cents: 300_000, balance_deduction_cents: 50_000)
      safe = Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                              opening_balance_cents: 2_000_000, balance_cents: 2_000_000)
      Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: safe, user: owner,
                                           amount_cents: 1_200_000, voucher_date: payroll_month,
                                           party_type: "User", party_id: staff.id).call

      get admin_accounting_monthly_payroll_path, params: { payroll_month: payroll_month.strftime("%Y-%m") }

      row_doc = Nokogiri::HTML(response.body).at_css("td.font-medium", text: "Advance Taker").parent
      payout_cell = row_doc.css("td")[8]
      expect(payout_cell.text).to include("2,500.00")
      expect(payout_cell.text).to include(I18n.t("accounting.monthly_payroll.payout_deduction", amount: "500.00"))
    end

    it "shows a negative remaining pay as owed to the company when penalties exceed salary" do
      payroll_month = Date.current.beginning_of_month
      staff = create(:user, company: company, name: "Over Penalized", role: "cashier",
                     monthly_salary_cents: 300_000)
      PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "fixed",
        amount_cents: 350_000,
        payroll_month: payroll_month,
        happened_at: Date.current
      )

      get admin_accounting_monthly_payroll_path, params: { payroll_month: payroll_month.strftime("%Y-%m") }

      expect(response).to have_http_status(:ok)
      row_doc = Nokogiri::HTML(response.body).at_css("td.font-medium", text: "Over Penalized").parent
      remaining_pay_cell = row_doc.css("td")[7]
      expect(remaining_pay_cell.text).to include("500.00")
      expect(remaining_pay_cell.text).not_to include("-500.00")
      expect(remaining_pay_cell.text).to include(I18n.t("staff.wages_ledger.they_owe"))
      expect(remaining_pay_cell["class"]).to include("text-red-700")

      total_row = Nokogiri::HTML(response.body).at_css("tfoot tr")
      totals_remaining_cell = total_row.css("td")[7]
      expect(totals_remaining_cell.text).to include("-500.00")
    end
  end

  describe "GET /admin/accounting/monthly_payroll/export" do
    before { sign_in owner }

    it "exports CSV with base salary and attendance pay columns" do
      create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)

      get admin_accounting_monthly_payroll_export_path, params: { payroll_month: "2026-07" }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("monthly-payroll-2026-07.csv")
      expect(response.body).to include(I18n.t("accounting.monthly_payroll.base_salary"))
      expect(response.body).to include(I18n.t("accounting.monthly_payroll.attendance_pay"))
    end

    it "exports the real negative remaining pay when penalties exceed salary" do
      payroll_month = Date.current.beginning_of_month
      staff = create(:user, company: company, name: "Over Penalized", role: "cashier",
                     monthly_salary_cents: 300_000)
      PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "fixed",
        amount_cents: 350_000,
        payroll_month: payroll_month,
        happened_at: Date.current
      )

      get admin_accounting_monthly_payroll_export_path, params: { payroll_month: payroll_month.strftime("%Y-%m") }

      expect(response).to have_http_status(:ok)
      rows = CSV.parse(response.body)
      row = rows.find { |r| r[0] == "Over Penalized" }
      totals_row = rows.last

      expect(row[8]).to eq("-500.00")
      expect(totals_row[8]).to eq("-500.00")
    end

    it "includes the location slug in the filename when filtered" do
      downtown = create(:location, company: company, name: "Downtown", slug: "downtown")
      create(:location, company: company, name: "Uptown", slug: "uptown")
      create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)

      get admin_accounting_monthly_payroll_export_path,
        params: { payroll_month: "2026-07", location_id: downtown.id }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("monthly-payroll-2026-07-downtown.csv")
    end

    it "includes company-wide in the filename for that filter" do
      create(:location, company: company, name: "Downtown")
      create(:location, company: company, name: "Uptown")
      create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000, all_locations: true)

      get admin_accounting_monthly_payroll_export_path,
        params: { payroll_month: "2026-07", location_id: StaffLocationFilter::COMPANY_WIDE_FILTER }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("monthly-payroll-2026-07-company-wide.csv")
    end
  end
end
