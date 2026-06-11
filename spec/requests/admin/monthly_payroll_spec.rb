# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::MonthlyPayroll", type: :request do
  include Devise::Test::IntegrationHelpers

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
  end
end
