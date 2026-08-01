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

    it "sorts rows by net pay descending" do
      create(:user, company: company, name: "Lower Paid", role: "cashier", monthly_salary_cents: 100_000)
      create(:user, company: company, name: "Higher Paid", role: "kitchen", monthly_salary_cents: 400_000)

      get admin_accounting_monthly_payroll_path, params: { sort: "net_pay_cents", direction: "desc" }

      expect(response).to have_http_status(:ok)
      expect(response.body.index("Higher Paid")).to be < response.body.index("Lower Paid")
    end
  end
end
