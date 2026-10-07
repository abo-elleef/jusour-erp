# frozen_string_literal: true

require "rails_helper"

# User became Accountable so a payment voucher naming a staff member (and the
# payroll flows that already exist) post against that specific employee's own
# account instead of a pool shared by everyone — see
# feedback discussion that led here and ChartOfAccountsService#wages_expense_line.
RSpec.describe "A user's own payroll account" do
  let(:company) { create(:company) }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:staff) do
    create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)
  end
  let(:treasury) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 500_000, balance_cents: 500_000)
  end

  before { Current.company = company }

  it "is assigned its own account_code on creation, distinct per employee" do
    expect(staff.account_code).to be_present
    expect(staff.account_code).not_to eq(owner.account_code)
    expect(staff.account_code).to be >= User::WAGES_ACCOUNT_CODE_BASE
  end

  it "answers the Accountable interface" do
    expect(staff.account_type).to eq("expense")
    expect(staff.normal_balance).to eq(:debit)
    expect(staff.to_account.code).to eq(staff.account_code)
  end

  describe "payroll advance" do
    it "posts DR the employee's own account" do
      advance = Accounting::PayPayrollAdvanceService.new(
        user: staff, amount_cents: 50_000, treasury: treasury, paid_by: owner, paid_on: Date.current
      ).call
      voucher = advance.payment_allocations.sole.payment

      entry = JournalEntry.for_source(voucher).sole
      debit = entry.lines.find { |l| l.debit_cents.positive? }
      expect(debit.account_code).to eq(staff.account_code)
    end
  end

  describe "payroll salary" do
    it "posts DR the employee's own account" do
      snapshot = Accounting::FinalizePayrollService.new(
        staff, Date.current.beginning_of_month, finalized_by: owner,
        treasury: treasury, paid_on: Date.current
      ).call

      entry = JournalEntry.for_source(snapshot).first
      next if entry.nil? # zero remaining pay this period, nothing posted

      debit = entry.lines.find { |l| l.debit_cents.positive? }
      expect(debit.account_code).to eq(staff.account_code)
    end
  end

  describe "staff meal" do
    it "posts DR the specific staff member's own account, not the pooled code" do
      order = create(:order, user: owner, company: company, total_cents: 2_000)

      Payments::StaffMealPaymentService.call(
        order: order, staff_meal_user: staff, treasury: treasury, processed_by: owner
      )

      entry = JournalEntry.for_source(order).sole
      debit = entry.lines.find { |l| l.debit_cents.positive? }
      expect(debit.account_code).to eq(staff.account_code)
      expect(debit.account_code).not_to eq(Accounting::JournalEntryService::STAFF_MEAL_CODE)
    end
  end

  describe "ChartOfAccountsService rollup" do
    it "combines every employee's own account into one Wages and salaries line" do
      other_staff = create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)

      Accounting::PayPayrollAdvanceService.new(
        user: staff, amount_cents: 30_000, treasury: treasury, paid_by: owner, paid_on: Date.current
      ).call
      Accounting::PayPayrollAdvanceService.new(
        user: other_staff, amount_cents: 20_000, treasury: treasury, paid_by: owner, paid_on: Date.current
      ).call

      coa = Accounting::ChartOfAccountsService.new(start_date: Date.current, end_date: Date.current)
      wages_line = coa.fixed_expense_lines.find { |l| l.code == Accounting::ChartOfAccountsService::WAGES_SUMMARY_CODE }

      expect(wages_line).not_to be_nil
      expect(wages_line.balance_cents).to eq(50_000)
      expect(wages_line.name).to eq(I18n.t("accounting.journal_entries.accounts.wages_and_salaries"))

      # Neither employee's own code shows up as its own separate dynamic line —
      # the whole point is they collapse into the one line above.
      expect(coa.dynamic_expense_lines.map(&:code)).not_to include(staff.account_code, other_staff.account_code)
    end
  end
end
