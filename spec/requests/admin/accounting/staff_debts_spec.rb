# frozen_string_literal: true

require "rails_helper"

# Payroll pays the full salary; what an employee owes the company lives on its
# own report, where the accountant records repayments as receipt vouchers.
RSpec.describe "Staff debts report", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let!(:debtor) do
    create(:user, company: company, role: "cashier", name: "Karim Debtor", monthly_salary_cents: 300_000,
                  balance_deduction_cents: 100_000)
  end
  let!(:clear) { create(:user, company: company, role: "cashier", name: "Clear Account", monthly_salary_cents: 300_000) }
  let(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 5_000_000, balance_cents: 5_000_000)
  end

  before { sign_in owner }

  def voucher!(direction, cents, user: debtor)
    Accounting::RecordVoucherService.new(direction: direction, treasury: safe, user: owner,
                                         amount_cents: cents, voucher_date: Date.current,
                                         party_type: "User", party_id: user.id).call
  end

  def report_row(name)
    Nokogiri::HTML(response.body).css("tbody tr").find { |tr| tr.text.include?(name) }
  end

  it "is listed under Staff on the reports page" do
    get admin_reports_path
    expect(response.body).to include(I18n.t("accounting.staff_debts_report.title"))
  end

  it "says so when nobody owes the company" do
    get admin_accounting_staff_debts_reports_path
    expect(response.body).to include(I18n.t("accounting.staff_debts_report.empty"))
  end

  context "when an employee was paid ahead of what they earned" do
    before do
      voucher!(Voucher::PAYMENT, 1_200_000)
      voucher!(Voucher::PAYMENT, 10_000, user: clear)
      voucher!(Voucher::RECEIPT, 10_000, user: clear) # paid back: owes nothing
    end

    it "lists only those who owe, with what they owe, the plan, and what is due" do
      get admin_accounting_staff_debts_reports_path

      expect(response).to have_http_status(:ok)
      row = report_row("Karim Debtor")
      expect(row.text).to include("12,000.00") # owed
      expect(row.text).to include("1,000.00")  # plan, and due this month
      expect(response.body).not_to include("Clear Account")
    end

    it "links each row to a receipt voucher pre-filled with the employee" do
      get admin_accounting_staff_debts_reports_path

      link = report_row("Karim Debtor").at_css("a[href*='vouchers/new']")
      expect(link["href"]).to include("direction=receipt")
      expect(CGI.unescape(link["href"])).to include("party=User:#{debtor.id}")
    end

    it "counts a repayment this month against what is due and what they owe" do
      voucher!(Voucher::RECEIPT, 40_000)

      get admin_accounting_staff_debts_reports_path

      row = report_row("Karim Debtor")
      expect(row.text).to include("11,600.00") # 12,000 − 400
      expect(row.css("td")[3].text).to include("400.00")   # repaid this month
      expect(row.css("td")[4].text).to include("600.00")   # 1,000 plan − 400
    end

    it "does not count a voided repayment" do
      receipt = voucher!(Voucher::RECEIPT, 40_000)
      receipt.void!(user: owner, reason: :entered_in_error)

      get admin_accounting_staff_debts_reports_path

      row = report_row("Karim Debtor")
      expect(row.css("td")[1].text).to include("12,000.00")
      expect(row.css("td")[3].text).to include("0.00")
    end

    it "shows nothing due without a plan" do
      debtor.update!(balance_deduction_cents: nil)

      get admin_accounting_staff_debts_reports_path

      expect(report_row("Karim Debtor").css("td")[4].text).to include(I18n.t("accounting.shared.em_dash"))
    end
  end

  it "is refused without payroll access" do
    sign_in create(:user, company: company, role: "cashier")
    get admin_accounting_staff_debts_reports_path
    expect(response).not_to have_http_status(:ok)
  end
end
