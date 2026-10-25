# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffPayrollController, type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include Devise::Test::IntegrationHelpers
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
      expect(response.body).to include(I18n.t("staff.payroll_portal.to_pay_title"))
      expect(response.body).not_to include(I18n.t("staff.payroll_portal.pin_title"))
    end

    it "shows money paid this month and what is still owed after PIN verification" do
      travel_to Time.zone.local(2026, 6, 10, 10, 0, 0) do
        Accounting::RecordVoucherService.new(
          direction: Voucher::PAYMENT,
          treasury: treasury,
          user: owner,
          amount_cents: 100_000,
          voucher_date: Date.new(2026, 6, 10),
          party_type: "User",
          party_id: staff.id
        ).call

        verify_pin!(month: payroll_month)

        html = Nokogiri::HTML(response.body)
        expect(response.body).to include(I18n.t("staff.payroll_portal.advances_title"))
        # Open month: 3,000 pay less the 1,000 advance it will repay, not yet paid.
        expect(response.body).to include(format_amount(200_000))
        expect(response.body).to include(I18n.t("staff.payroll_portal.status_not_paid"))
        expect(response.body).to include(I18n.t("staff.payroll_portal.debt_title"))
        expect(html.css("[data-payment-kind]").map { |e| e["data-payment-kind"] }).to eq(%w[advance])
      end
    end

    it "shows a recorded month as this month's pay, paid, with the advance balance apart" do
      staff.update!(balance_deduction_cents: 50_000)
      travel_to Time.zone.local(2026, 6, 30, 10, 0, 0) do
        Accounting::RecordVoucherService.new(
          direction: Voucher::PAYMENT, treasury: treasury, user: owner, amount_cents: 200_000,
          voucher_date: Date.new(2026, 6, 10), party_type: "User", party_id: staff.id
        ).call
        sign_in owner
        post admin_user_payroll_snapshot_path(staff, payroll_month: payroll_month.strftime("%Y-%m")),
             params: { payroll_snapshot: { treasury_id: treasury.id, paid_on: Date.new(2026, 6, 30) } }
        expect(PayrollSnapshot.find_by!(user: staff, payroll_month: payroll_month).payout_voucher).to be_present

        verify_pin!(month: payroll_month)

        html = Nokogiri::HTML(response.body)
        hero = html.at_css("dl").ancestors("div").first.text
        expect(hero).to include(format_amount(250_000))  # 3,000 − 500 kept back
        expect(hero).to include(I18n.t("staff.payroll_portal.status_paid", date: I18n.l(Date.new(2026, 6, 30), format: :long)))
        expect(hero).to include(format_amount(50_000))
        expect(hero).not_to include(format_amount(450_000))  # never "paid this month" = advance + salary
        expect(response.body).to include(I18n.t("staff.payroll_portal.debt_title"))
        expect(response.body).to include(format_amount(150_000))  # 2,000 advance − 500 repaid
        expect(response.body).not_to include(format_money(250_000))  # amounts without the currency
        expect(html.css("[data-payment-kind]").map { |e| e["data-payment-kind"] }).to match_array(%w[salary advance])
        # Signed for the employee reading it: what they were paid is positive.
        expect(html.css("[data-payment-amount]").map { |e| e.text.strip }).to match_array(
          ["+#{format_amount(250_000)}", "+#{format_amount(200_000)}"]
        )
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

    it "locks the link for 15 minutes after 5 wrong PINs" do
      5.times { post verify_staff_payroll_path(token: staff.payroll_access_token), params: { pin: "0000" } }
      expect(staff.reload.payroll_pin_locked?).to be(true)

      post verify_staff_payroll_path(token: staff.payroll_access_token), params: { pin: "1234" }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include(I18n.t("staff.payroll_portal.pin_locked", minutes: 15))

      travel 16.minutes do
        post verify_staff_payroll_path(token: staff.payroll_access_token), params: { pin: "1234" }
        expect(response).to have_http_status(:redirect)
      end
    end

    it "clears the wrong-PIN count after a right PIN" do
      4.times { post verify_staff_payroll_path(token: staff.payroll_access_token), params: { pin: "0000" } }
      post verify_staff_payroll_path(token: staff.payroll_access_token), params: { pin: "1234" }
      expect(staff.reload.payroll_pin_failed_attempts).to eq(0)

      post verify_staff_payroll_path(token: staff.payroll_access_token), params: { pin: "0000" }
      expect(staff.reload.payroll_pin_locked?).to be(false)
    end

    it "drops expired unlocked links from the session" do
      other = create(:user, company: company, name: "Other Staff", email: "other-staff@example.com",
                     role: "cashier", monthly_salary_cents: 300_000, pin: "5678")
      verify_pin!

      travel 9.hours do
        post verify_staff_payroll_path(token: other.payroll_access_token), params: { pin: "5678" }
        expect(session[:staff_payroll_access].keys).to eq([other.payroll_access_token])
      end
    end

    it "locks the preview and requires PIN again" do
      verify_pin!

      delete lock_staff_payroll_path(token: staff.payroll_access_token)
      follow_redirect!

      expect(response.body).to include(I18n.t("staff.payroll_portal.pin_title"))
    end
  end
end
