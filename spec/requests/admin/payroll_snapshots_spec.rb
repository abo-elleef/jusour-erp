# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin payroll snapshots", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) do
    create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)
  end
  let(:payroll_month) { Date.current.beginning_of_month }

  before { Current.company = company }

  describe "POST /admin/users/:user_id/payroll_snapshot" do
    before { sign_in owner }

    it "records payroll for the selected month" do
      expect do
        post admin_user_payroll_snapshot_path(staff, payroll_month: payroll_month.strftime("%Y-%m"))
      end.to change(PayrollSnapshot, :count).by(1)

      snapshot = PayrollSnapshot.last
      expect(snapshot).to have_attributes(
        user: staff,
        base_salary_cents: 300_000,
        net_pay_cents: 300_000,
        finalized_by: owner
      )
      expect(response).to redirect_to(admin_user_path(staff, payroll_month: payroll_month.strftime("%Y-%m")))
    end

    it "keeps recorded payroll after salary changes" do
      post admin_user_payroll_snapshot_path(staff, payroll_month: payroll_month.strftime("%Y-%m"))
      staff.update!(monthly_salary_cents: 450_000)

      get admin_user_path(staff, payroll_month: payroll_month.strftime("%Y-%m"))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("staff.payroll.recorded"))
      expect(PayrollSnapshot.find_by!(user: staff, payroll_month: payroll_month).net_pay_cents).to eq(300_000)
    end
  end

  describe "POST /admin/accounting/monthly_payroll/finalize_all" do
    before { sign_in owner }

    it "records payroll for all pending staff" do
      staff
      second_staff = create(:user, company: company, role: "kitchen", monthly_salary_cents: 200_000)

      expect do
        post admin_accounting_monthly_payroll_finalize_all_path(payroll_month: payroll_month.strftime("%Y-%m"))
      end.to change(PayrollSnapshot, :count).by(2)

      expect(response).to redirect_to(admin_accounting_monthly_payroll_path(payroll_month: payroll_month.strftime("%Y-%m")))
      expect(PayrollSnapshot.pluck(:user_id)).to contain_exactly(staff.id, second_staff.id)
    end
  end
end
