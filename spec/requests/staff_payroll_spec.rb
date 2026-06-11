# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffPayrollController, type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ApplicationHelper

  let(:company) { create(:company) }
  let!(:staff) do
    create(:user,
      company: company,
      name: "Portal Staff",
      email: "portal-staff@example.com",
      role: "cashier",
      monthly_salary_cents: 300_000,
      pin: "1234")
  end
  let(:owner) { create(:user, :owner, company: company) }
  let(:treasury) do
    Treasury.create!(
      company: company,
      name: "Safe",
      treasury_type: "safe",
      opening_balance_cents: 500_000,
      balance_cents: 500_000
    )
  end
  let(:payroll_month) { Date.new(2026, 6, 1) }

  before { Current.company = company }

  def verify_pin!(month: nil)
    params = { pin: "1234" }
    params[:payroll_month] = month.strftime("%Y-%m") if month
    post verify_staff_payroll_path(token: staff.payroll_access_token), params: params
    follow_redirect!
  end

  describe "GET /staff/payroll/:token" do
    it "shows the PIN form without login" do
      get staff_payroll_path(token: staff.payroll_access_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("staff.payroll_portal.pin_title"))
    end

    it "shows payroll after PIN verification" do
      verify_pin!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("staff.payroll.remaining_pay"))
      expect(response.body).not_to include(I18n.t("staff.payroll_portal.pin_title"))
    end

    it "shows advances and remaining pay after PIN verification" do
      travel_to Time.zone.local(2026, 6, 10, 10, 0, 0) do
        Accounting::PayPayrollAdvanceService.new(
          user: staff,
          payroll_month: payroll_month,
          advance_slot: "mid_month",
          amount_cents: 100_000,
          treasury: treasury,
          paid_by: owner,
          paid_on: Date.new(2026, 6, 10)
        ).call

        verify_pin!(month: payroll_month)

        expect(response.body).to include(I18n.t("staff.payroll_portal.advances_title"))
        expect(response.body).to include(I18n.t("staff.payroll.advances.slots.mid_month"))
        expect(response.body).to include(format_money(100_000))
        expect(response.body).to include(format_money(200_000))
      end
    end

    it "preserves the selected month through PIN verification" do
      post verify_staff_payroll_path(token: staff.payroll_access_token),
        params: { pin: "1234", payroll_month: payroll_month.strftime("%Y-%m") }

      expect(response).to redirect_to(
        staff_payroll_path(token: staff.payroll_access_token, payroll_month: payroll_month.strftime("%Y-%m"))
      )
    end

    it "rejects an incorrect PIN" do
      post verify_staff_payroll_path(token: staff.payroll_access_token), params: { pin: "9999" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("staff.payroll_portal.invalid_pin"))
    end

    it "locks the preview and requires PIN again" do
      verify_pin!

      delete lock_staff_payroll_path(token: staff.payroll_access_token)
      follow_redirect!

      expect(response.body).to include(I18n.t("staff.payroll_portal.pin_title"))
    end
  end
end
