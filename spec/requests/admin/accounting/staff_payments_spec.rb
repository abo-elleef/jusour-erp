# frozen_string_literal: true

require "rails_helper"

# Paying staff is an ordinary voucher with the employee as its party. Going
# past what they're owed plus a month's salary is a warning, not a block: the
# form comes back once, and confirming issues it.
RSpec.describe "Money to staff", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:staff)   { create(:user, company: company, role: "cashier", name: "Mona", monthly_salary_cents: 300_000) }
  let(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 1_000_000, balance_cents: 1_000_000)
  end

  before { sign_in owner }

  def pay(pounds, confirm: false)
    post admin_accounting_vouchers_path, params: {
      voucher: { direction: Voucher::PAYMENT, treasury_id: safe.id, voucher_date: Date.current,
                 amount_pounds: pounds, party_selection: "User:#{staff.id}" },
      confirm_over_cap: (confirm ? "1" : nil)
    }.compact
  end

  describe "the payment cap" do
    it "issues a payment within the cap straight away" do
      expect { pay("3000") }.to change(Voucher, :count).by(1)
      expect(Voucher.last.party).to eq(staff)
    end

    it "warns instead of issuing when the payment is over the cap" do
      expect { pay("3500") }.not_to change(Voucher, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("accounting.vouchers.staff_cap.confirm"))
    end

    it "issues it once the warning is confirmed" do
      expect { pay("3500", confirm: true) }.to change(Voucher, :count).by(1)
      expect(staff.staff_balance_cents).to eq(-350_000)
    end
  end

  it "pre-selects the employee when opened from their page" do
    get new_admin_accounting_voucher_path(direction: Voucher::RECEIPT, party: "User:#{staff.id}")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("User:#{staff.id}")
  end

  describe "finalizing a month for someone who owes the company" do
    let(:month) { Date.current.beginning_of_month }

    before do
      Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: safe, user: owner,
                                           amount_cents: 1_200_000, voucher_date: month,
                                           party_type: "User", party_id: staff.id).call
    end

    it "shows the debt and the deduction field on the staff page" do
      get_user_tab(staff, "payroll", payroll_month: month.strftime("%Y-%m"))
      expect(response.body).to include(I18n.t("staff.payroll.deduction.field"))
      expect(response.body).to include("payroll_snapshot[deduction_pounds]")
    end

    it "keeps back the amount typed and pays out the rest" do
      post admin_user_payroll_snapshot_path(staff, payroll_month: month.strftime("%Y-%m")),
           params: { payroll_snapshot: { treasury_id: safe.id, paid_on: month, deduction_pounds: "500" } }

      snapshot = PayrollSnapshot.find_by!(user: staff, payroll_month: month)
      expect(snapshot.deduction_cents).to eq(50_000)
      expect(snapshot.payout_voucher.amount_cents).to eq(250_000)
    end

    it "saves a standing plan from the staff form" do
      patch admin_user_path(staff), params: { user: { balance_deduction_pounds: "750" } }
      expect(staff.reload.balance_deduction_cents).to eq(75_000)
    end
  end

  describe "the staff payments report" do
    it "is listed under Staff on the reports page" do
      get admin_reports_path
      expect(response.body).to include(I18n.t("accounting.staff_payments_report.title"))
    end

    it "shows each employee's salary against what went to them in the month" do
      Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: safe, user: owner,
                                           amount_cents: 120_000, voucher_date: Date.current,
                                           party_type: "User", party_id: staff.id).call
      Accounting::RecordVoucherService.new(direction: Voucher::RECEIPT, treasury: safe, user: owner,
                                           amount_cents: 20_000, voucher_date: Date.current,
                                           party_type: "User", party_id: staff.id).call

      get admin_accounting_staff_payments_reports_path(payroll_month: Date.current.strftime("%Y-%m"))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mona")
      expect(response.body).to include("3,000.00") # monthly salary
      expect(response.body).to include("1,000.00") # net paid: 1,200 out, 200 back
    end

    it "is refused without payroll access" do
      cashier = create(:user, company: company, role: "cashier")
      sign_in cashier
      get admin_accounting_staff_payments_reports_path
      expect(response).not_to have_http_status(:ok)
    end
  end
end
