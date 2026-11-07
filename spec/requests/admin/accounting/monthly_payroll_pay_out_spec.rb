# frozen_string_literal: true

require "rails_helper"

# Lock the figures on the month's last day ("Record only — pay later"), pay
# on the 3rd of the next month from the monthly payroll page.
RSpec.describe "Paying out recorded payroll", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let!(:mona)   { create(:user, company: company, role: "cashier", name: "Mona", monthly_salary_cents: 300_000) }
  let!(:omar)   { create(:user, company: company, role: "cashier", name: "Omar", monthly_salary_cents: 200_000) }
  let(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 1_000_000, balance_cents: 1_000_000)
  end
  let(:october) { Date.new(2026, 10, 1) }
  let(:paid_on) { Date.new(2026, 11, 3) }

  before do
    travel_to Time.zone.local(2026, 10, 31, 18)
    [mona, omar].each do |user|
      Accounting::FinalizePayrollService.new(user, october, finalized_by: owner).call
    end
    travel_to Time.zone.local(2026, 11, 3, 10)
    sign_in owner
  end

  after { travel_back }

  def pay_out(**extra)
    post admin_accounting_monthly_payroll_pay_out_path(payroll_month: "2026-10", **extra),
         params: { payroll_snapshot: { treasury_id: safe.id, paid_on: paid_on } }
  end

  def snapshot_for(user) = PayrollSnapshot.find_by(user: user, payroll_month: october)

  it "shows the recorded month as waiting to be paid" do
    get admin_accounting_monthly_payroll_path(payroll_month: "2026-10")

    expect(response.body).to include(I18n.t("accounting.monthly_payroll.pay_all", count: 2))
    expect(response.body).to include(I18n.t("staff.payroll.awaiting_payout"))
  end

  it "pays everyone owed, dated the payment day, with the accrual left on the month's last day" do
    expect { pay_out }.to change(Voucher, :count).by(2)

    expect(flash[:notice]).to eq(I18n.t("flash.payroll_snapshot.bulk_paid", count: 2))
    expect(snapshot_for(mona).payout_voucher.voucher_date).to eq(paid_on)
    expect(snapshot_for(mona).remaining_pay_cents).to eq(300_000)
    expect(snapshot_for(omar).remaining_pay_cents).to eq(200_000)
    expect(safe.reload.balance_cents).to eq(500_000)
    expect(JournalEntry.for_source(snapshot_for(mona)).first.date).to eq(october.end_of_month)
    expect(mona.staff_balance_cents).to eq(0)
  end

  it "counts the payout in October, not November" do
    pay_out

    expect(Accounting::MonthlyPayrollService.new(mona, october).call.paid_cents).to eq(300_000)
    expect(mona.staff_paid_cents_for_month(Date.new(2026, 11, 1))).to eq(0)
  end

  it "pays a single employee from their row" do
    expect { pay_out(user_id: mona.id) }.to change(Voucher, :count).by(1)

    expect(snapshot_for(mona).paid_out?).to be(true)
    expect(snapshot_for(omar).paid_out?).to be(false)
  end

  it "doesn't pay twice" do
    pay_out
    expect { pay_out }.not_to change(Voucher, :count)
    expect(flash[:notice]).to eq(I18n.t("flash.payroll_snapshot.nothing_to_pay"))
  end

  it "doesn't pay again what was already paid by hand after the month ended" do
    Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: safe, user: owner,
                                         amount_cents: 300_000, voucher_date: Date.new(2026, 11, 2),
                                         party_type: "User", party_id: mona.id).call

    expect { pay_out }.to change(Voucher, :count).by(1)
    expect(snapshot_for(mona).paid_out?).to be(false)
    expect(snapshot_for(omar).paid_out?).to be(true)
  end

  it "takes the month's own advance off the pay when the month was locked" do
    sara = create(:user, company: company, role: "cashier", name: "Sara", monthly_salary_cents: 200_000)
    Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: safe, user: owner,
                                         amount_cents: 100_000, voucher_date: Date.new(2026, 10, 10),
                                         party_type: "User", party_id: sara.id).call
    Accounting::FinalizePayrollService.new(sara, october, finalized_by: owner).call

    pay_out

    # Sara took 1,000 early in October: 2,000 earned, 1,000 already had.
    expect(snapshot_for(sara).deduction_cents).to eq(0)
    expect(snapshot_for(sara).remaining_pay_cents).to eq(100_000)
    expect(sara.staff_balance_cents).to eq(0)
  end

  describe "for someone who owes the company from an earlier month" do
    let(:karim) do
      create(:user, company: company, role: "cashier", name: "Karim", monthly_salary_cents: 200_000,
                    balance_deduction_cents: 100_000)
    end

    before do
      # Karim took 4,000 in September. His repayment plan is only a reminder.
      Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: safe, user: owner,
                                           amount_cents: 400_000, voucher_date: Date.new(2026, 9, 10),
                                           party_type: "User", party_id: karim.id).call
      Accounting::FinalizePayrollService.new(karim, october, finalized_by: owner).call
    end

    it "pays the whole month and leaves the debt owed" do
      expect(snapshot_for(karim).payout_due_cents(on: paid_on)).to eq(200_000)

      pay_out(user_id: karim.id)

      expect(snapshot_for(karim).payout_voucher.amount_cents).to eq(200_000)
      expect(karim.staff_balance_cents).to eq(-400_000)
    end

    it "shows the payout on the payroll page" do
      row = Accounting::MonthlyPayrollService.new(karim, october).call

      expect(row.payout_cents).to eq(200_000)
    end

    it "takes off what was paid by hand after the month ended" do
      Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: safe, user: owner,
                                           amount_cents: 40_000, voucher_date: Date.new(2026, 11, 2),
                                           party_type: "User", party_id: karim.id).call

      expect(snapshot_for(karim).payout_due_cents(on: paid_on)).to eq(160_000)
    end
  end

  it "offers record and pay in one form, sharing one treasury and date" do
    sara = create(:user, company: company, role: "cashier", name: "Sara", monthly_salary_cents: 200_000,
                  employment_start_on: Date.new(2026, 1, 1))
    sara.update!(monthly_salary_cents: 200_000)

    get admin_accounting_monthly_payroll_path(payroll_month: "2026-10")

    doc = Nokogiri::HTML(response.body)
    pay = doc.at_css("input[type=submit][formaction*='pay_out']")
    panel = pay.ancestors("form").first
    expect(panel.css("select[name='payroll_snapshot[treasury_id]']").size).to eq(1)
    expect(panel.css("input[name='payroll_snapshot[paid_on]']").size).to eq(1)
    record = doc.css("input[type=submit]").find { |i| i["value"] == I18n.t("accounting.monthly_payroll.record_all_count", count: 1) }
    expect(pay).to be_present
    expect(record).to be_present
  end

  it "needs a treasury" do
    post admin_accounting_monthly_payroll_pay_out_path(payroll_month: "2026-10"),
         params: { payroll_snapshot: { treasury_id: "", paid_on: paid_on } }

    expect(flash[:alert]).to eq(I18n.t("flash.payroll_snapshot.pay_treasury_required"))
    expect(Voucher.count).to eq(0)
  end

  it "re-recording a paid month voids its payout and leaves it owed again" do
    pay_out
    voucher = snapshot_for(mona).payout_voucher
    Current.company = company

    Accounting::FinalizePayrollService.new(mona, october, finalized_by: owner).call

    expect(voucher.reload.voided_at).to be_present
    expect(snapshot_for(mona).paid_out?).to be(false)
    expect(snapshot_for(mona).payout_due_cents(on: paid_on)).to eq(300_000)
  end
end
