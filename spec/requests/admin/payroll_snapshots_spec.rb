# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin payroll snapshots", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) do
    create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)
  end
  let(:treasury) do
    Treasury.create!(
      company: company,
      name: "Main Safe",
      treasury_type: "safe",
      opening_balance_cents: 500_000,
      balance_cents: 500_000
    )
  end
  let(:payroll_month) { Date.current.beginning_of_month }

  before { Current.company = company }

  describe "POST /admin/users/:user_id/payroll_snapshot" do
    before { sign_in owner }

    it "records payroll for the selected month and debits remaining pay from treasury" do
      expect do
        post admin_user_payroll_snapshot_path(staff, payroll_month: payroll_month.strftime("%Y-%m")),
          params: {
            payroll_snapshot: {
              treasury_id: treasury.id,
              paid_on: payroll_month.end_of_month
            }
          }
      end.to change(PayrollSnapshot, :count).by(1)
        .and change(TreasuryTransaction, :count).by(1)

      snapshot = PayrollSnapshot.last
      expect(snapshot).to have_attributes(
        user: staff,
        base_salary_cents: 300_000,
        net_pay_cents: 300_000,
        remaining_pay_cents: 300_000,
        treasury: treasury,
        finalized_by: owner
      )

      transaction = TreasuryTransaction.last
      expect(transaction).to have_attributes(
        kind: "payroll_salary",
        amount_cents: -300_000,
        source_record: snapshot
      )
      expect(treasury.reload.balance_cents).to eq(200_000)
      expect(response).to redirect_to(admin_user_path(staff, payroll_month: payroll_month.strftime("%Y-%m")))
    end

    it "debits only remaining pay when advances were already paid" do
      Accounting::PayPayrollAdvanceService.new(
        user: staff,
        payroll_month: payroll_month,
        advance_slot: "mid_month",
        amount_cents: 100_000,
        treasury: treasury,
        paid_by: owner,
        paid_on: payroll_month.change(day: 10)
      ).call

      expect(treasury.reload.balance_cents).to eq(400_000)

      post admin_user_payroll_snapshot_path(staff, payroll_month: payroll_month.strftime("%Y-%m")),
        params: {
          payroll_snapshot: {
            treasury_id: treasury.id,
            paid_on: payroll_month.end_of_month
          }
        }

      snapshot = PayrollSnapshot.last
      expect(snapshot.remaining_pay_cents).to eq(200_000)
      expect(treasury.reload.balance_cents).to eq(200_000)
      expect(TreasuryTransaction.where(kind: "payroll_salary").count).to eq(1)
      expect(TreasuryTransaction.where(kind: "payroll_salary").last.amount_cents).to eq(-200_000)
    end

    it "keeps recorded payroll after salary changes" do
      post admin_user_payroll_snapshot_path(staff, payroll_month: payroll_month.strftime("%Y-%m")),
        params: {
          payroll_snapshot: {
            treasury_id: treasury.id,
            paid_on: payroll_month.end_of_month
          }
        }
      staff.update!(monthly_salary_cents: 450_000)

      get admin_user_path(staff, payroll_month: payroll_month.strftime("%Y-%m"))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("staff.payroll.recorded"))
      expect(PayrollSnapshot.find_by!(user: staff, payroll_month: payroll_month).net_pay_cents).to eq(300_000)
    end
  end

  describe "DELETE /admin/users/:user_id/payroll_snapshot" do
    before { sign_in owner }

    it "removes a recorded payroll snapshot and restores treasury balance" do
      post admin_user_payroll_snapshot_path(staff, payroll_month: payroll_month.strftime("%Y-%m")),
        params: {
          payroll_snapshot: {
            treasury_id: treasury.id,
            paid_on: payroll_month.end_of_month
          }
        }

      expect(treasury.reload.balance_cents).to eq(200_000)

      expect do
        delete admin_user_payroll_snapshot_path(staff, payroll_month: payroll_month.strftime("%Y-%m"))
      end.to change(PayrollSnapshot, :count).by(-1)
        .and change(TreasuryTransaction, :count).by(-1)

      expect(treasury.reload.balance_cents).to eq(500_000)
      expect(response).to redirect_to(admin_user_path(staff, payroll_month: payroll_month.strftime("%Y-%m")))
      follow_redirect!

      expect(response.body).to include(I18n.t("staff.payroll.record_payroll"))
      expect(response.body).not_to include(I18n.t("staff.payroll.recorded"))
    end

    it "returns to monthly payroll when requested" do
      post admin_user_payroll_snapshot_path(staff, payroll_month: payroll_month.strftime("%Y-%m")),
        params: {
          payroll_snapshot: {
            treasury_id: treasury.id,
            paid_on: payroll_month.end_of_month
          }
        }

      delete admin_user_payroll_snapshot_path(
        staff,
        payroll_month: payroll_month.strftime("%Y-%m"),
        return_to: "monthly_payroll"
      )

      expect(response).to redirect_to(admin_accounting_monthly_payroll_path(payroll_month: payroll_month.strftime("%Y-%m")))
    end
  end

  describe "POST /admin/accounting/monthly_payroll/finalize_all" do
    before { sign_in owner }

    it "records payroll for all pending staff and debits treasuries" do
      staff
      second_staff = create(:user, company: company, role: "kitchen", monthly_salary_cents: 200_000)

      expect do
        post admin_accounting_monthly_payroll_finalize_all_path(payroll_month: payroll_month.strftime("%Y-%m")),
          params: {
            payroll_snapshot: {
              treasury_id: treasury.id,
              paid_on: payroll_month.end_of_month
            }
          }
      end.to change(PayrollSnapshot, :count).by(2)
        .and change(TreasuryTransaction.where(kind: "payroll_salary"), :count).by(2)

      expect(response).to redirect_to(admin_accounting_monthly_payroll_path(payroll_month: payroll_month.strftime("%Y-%m")))
      expect(PayrollSnapshot.pluck(:user_id)).to contain_exactly(staff.id, second_staff.id)
      expect(treasury.reload.balance_cents).to eq(0)
    end
  end
end
