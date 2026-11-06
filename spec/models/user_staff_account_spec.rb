# frozen_string_literal: true

require "rails_helper"

# Every employee is an account: finalizing a month credits it with what they
# earned (Dr Salaries 5501), every voucher paid to them debits it, every
# voucher received from them credits it, and staff meals debit it. There is no
# separate "advance" — paying before the month is finalized is just a payment
# voucher. See User::WAGES_ACCOUNT_CODE_BASE.
RSpec.describe "A staff member's own account" do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:staff)   { create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000) }
  let(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 1_000_000, balance_cents: 1_000_000)
  end
  let(:month) { Date.new(2026, 6, 1) }

  before { Current.company = company }
  around { |example| travel_to(Time.zone.local(2026, 6, 20, 10)) { example.run } }

  def voucher!(direction, cents, date: Date.new(2026, 6, 10))
    Accounting::RecordVoucherService.new(
      direction: direction, treasury: safe, user: owner, amount_cents: cents,
      voucher_date: date, party_type: "User", party_id: staff.id
    ).call
  end

  def finalize!(treasury: nil)
    Accounting::FinalizePayrollService.new(staff, month, finalized_by: owner,
                                           treasury: treasury, paid_on: Date.new(2026, 6, 30)).call
  end

  it "gets its own liability code, distinct per employee" do
    expect(staff.account_code).to be > User::WAGES_ACCOUNT_CODE_BASE
    expect(staff.account_code).not_to eq(owner.account_code)
    expect(staff.account_type).to eq("liability")
    expect(staff.normal_balance).to eq(:credit)
  end

  it "skips a code a treasury already holds" do
    owner
    next_code = User.unscoped.where(company_id: company.id).maximum(:wages_account_code) + 1
    Treasury.create!(company: company, name: "Clash", treasury_type: "other", account_code: next_code)

    expect(create(:user, company: company).account_code).to eq(next_code + 1)
  end

  describe "a payment voucher to the employee" do
    it "debits their account and is tagged as a staff payment" do
      voucher = voucher!(Voucher::PAYMENT, 50_000)

      debit = JournalEntry.for_source(voucher).sole.lines.find { |l| l.debit_cents.positive? }
      expect(debit.account_code).to eq(staff.account_code)
      expect(TreasuryTransaction.find_by(source_record: voucher).kind).to eq("staff_payment")
      expect(staff.staff_balance_cents).to eq(-50_000)
    end

    it "is undone by voiding it" do
      voucher!(Voucher::PAYMENT, 50_000).void!(user: owner)
      expect(staff.staff_balance_cents).to eq(0)
      expect(safe.reload.balance_cents).to eq(1_000_000)
    end
  end

  it "a receipt voucher from the employee credits their account" do
    voucher!(Voucher::PAYMENT, 50_000)
    voucher!(Voucher::RECEIPT, 20_000)

    expect(staff.staff_balance_cents).to eq(-30_000)
    expect(staff.staff_paid_cents_for_month(month)).to eq(30_000)
  end

  describe "finalizing the month" do
    it "credits what was earned, so payments made during the month come off it" do
      voucher!(Voucher::PAYMENT, 100_000)
      snapshot = finalize!

      accrual = JournalEntry.for_source(snapshot).sole
      expect(accrual.lines.find { |l| l.debit_cents.positive? }.account_code)
        .to eq(Accounting::JournalEntryService::SALARY_CODE)
      expect(accrual.lines.find { |l| l.credit_cents.positive? }.account_code).to eq(staff.account_code)

      expect(snapshot.net_pay_cents).to eq(300_000)
      expect(snapshot.advances_cents).to eq(100_000)
      expect(staff.staff_balance_cents).to eq(200_000)
      expect(snapshot.payout_voucher).to be_nil
    end

    it "pays the balance out with a voucher when given a treasury" do
      voucher!(Voucher::PAYMENT, 100_000)
      snapshot = finalize!(treasury: safe)

      expect(snapshot.payout_voucher).to be_payment
      expect(snapshot.payout_voucher.party).to eq(staff)
      expect(snapshot.remaining_pay_cents).to eq(200_000)
      expect(staff.staff_balance_cents).to eq(0)
      expect(safe.reload.balance_cents).to eq(1_000_000 - 300_000)
    end

    it "pays nothing out when they were already paid more than they earned" do
      voucher!(Voucher::PAYMENT, 350_000)
      snapshot = finalize!(treasury: safe)

      expect(snapshot.payout_voucher).to be_nil
      expect(staff.staff_balance_cents).to eq(-50_000)
    end
  end

  # What they owe from earlier months is repaid separately (receipt voucher,
  # Staff debts report); payroll never keeps any of it back.
  describe "a large advance from an earlier month" do
    before { voucher!(Voucher::PAYMENT, 1_200_000, date: Date.new(2026, 5, 10)) } # 4× the salary

    it "pays the whole month and leaves the debt alone" do
      snapshot = finalize!(treasury: safe)

      expect(snapshot.deduction_cents).to eq(0)
      expect(snapshot.payout_voucher.amount_cents).to eq(300_000)
      expect(staff.staff_balance_cents).to eq(-1_200_000)
    end

    it "ignores the standing repayment plan" do
      staff.update!(balance_deduction_cents: 75_000)
      snapshot = finalize!(treasury: safe)

      expect(snapshot.payout_voucher.amount_cents).to eq(300_000)
    end

    it "only takes this month's own advance off this month's pay" do
      voucher!(Voucher::PAYMENT, 50_000)
      snapshot = finalize!(treasury: safe)

      expect(snapshot.payout_voucher.amount_cents).to eq(250_000)
      expect(staff.staff_balance_cents).to eq(-1_200_000)
    end

    it "previews the full payout before the month is finalized" do
      summary = Accounting::MonthlyPayrollService.new(staff, month).call

      expect(summary.deduction_cents).to eq(0)
      expect(summary.payout_cents).to eq(300_000)
      expect(summary.still_to_pay_cents).to eq(300_000)
      expect(summary.debt_after_cents).to eq(1_200_000)
    end

    it "is repaid by a receipt voucher, which lowers what they owe" do
      finalize!(treasury: safe)
      voucher!(Voucher::RECEIPT, 100_000, date: Date.new(2026, 6, 30))

      expect(staff.staff_balance_cents).to eq(-1_100_000)
    end
  end

  it "treats a blank or zero plan as no plan" do
    staff.update!(balance_deduction_pounds: "")
    expect(staff.balance_deduction_cents).to be_nil
    staff.update!(balance_deduction_pounds: "0")
    expect(staff.balance_deduction_cents).to be_nil
  end

  it "a staff meal debits the employee's account" do
    order = create(:order, user: owner, company: company, total_cents: 2_000)
    Payments::StaffMealPaymentService.call(order: order, staff_meal_user: staff, treasury: safe, processed_by: owner)

    debit = JournalEntry.for_source(order).sole.lines.find { |l| l.debit_cents.positive? }
    expect(debit.account_code).to eq(staff.account_code)
  end

  describe "on the statements" do
    it "puts earnings on the P&L as one Wages and salaries line, and the unpaid balance under liabilities" do
      voucher!(Voucher::PAYMENT, 100_000)
      finalize!

      coa = Accounting::ChartOfAccountsService.new(start_date: month, end_date: month.end_of_month)
      wages = coa.fixed_expense_lines.find { |l| l.code == Accounting::ChartOfAccountsService::WAGES_SUMMARY_CODE }
      expect(wages.balance_cents).to eq(300_000)
      expect(coa.dynamic_expense_lines.map(&:code)).not_to include(staff.account_code)

      expect(coa.staff_balance_line.balance_cents).to eq(200_000)
      expect(coa.other_liability_lines.map(&:code)).not_to include(staff.account_code)
    end
  end

  it "cannot be deleted once money has moved to them" do
    voucher!(Voucher::PAYMENT, 10_000)
    expect(staff.destroy).to be(false)
  end
end
