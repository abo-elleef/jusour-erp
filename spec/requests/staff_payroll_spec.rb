# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffPayrollController, type: :request do
  let!(:staff) do
    User.create!(
      name: "Portal Staff",
      email: "portal-staff@example.com",
      role: "cashier",
      password: "password123",
      monthly_salary_cents: 300_000,
      pin: "1234"
    )
  end

  describe "GET /staff/payroll/:token" do
    it "shows the PIN form without login" do
      get staff_payroll_path(token: staff.payroll_access_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("staff.payroll_portal.pin_title"))
    end

    it "shows payroll after PIN verification" do
      post verify_staff_payroll_path(token: staff.payroll_access_token), params: { pin: "1234" }
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("staff.payroll.net_pay"))
      expect(response.body).not_to include(I18n.t("staff.payroll_portal.pin_title"))
    end

    it "rejects an incorrect PIN" do
      post verify_staff_payroll_path(token: staff.payroll_access_token), params: { pin: "9999" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("staff.payroll_portal.invalid_pin"))
    end
  end
end
