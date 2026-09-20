# frozen_string_literal: true

require "rails_helper"

# Advances happen daily here — 226 of them, 228,966 — and left no document.
# They are vouchers now, settling the advance against the advances account
# (5500), which is exactly the entry they posted before.
RSpec.describe "Paying a payroll advance" do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:staff)   { create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000) }
  let(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 500_000, balance_cents: 500_000)
  end

  def pay!(amount_cents: 100_000, paid_on: Date.new(2026, 6, 15))
    Accounting::PayPayrollAdvanceService.new(
      user: staff, amount_cents: amount_cents, treasury: safe,
      paid_by: owner, paid_on: paid_on
    ).call
  end

  around { |example| travel_to(Time.zone.local(2026, 6, 15, 10)) { example.run } }

  it "issues a payment voucher naming the employee" do
    advance = pay!

    voucher = advance.payment_allocations.sole.payment
    expect(voucher).to be_a(Voucher)
    expect(voucher).to be_payment
    expect(voucher.counterparty).to eq(staff.name)
    expect(voucher.voucher_date).to eq(Date.new(2026, 6, 15))
    expect(voucher.amount_cents).to eq(100_000)
  end

  it "posts the same entry it always did — DR advances, CR the treasury" do
    advance = pay!
    voucher = advance.payment_allocations.sole.payment

    entry = JournalEntry.for_source(voucher).sole
    expect(entry.lines.sum(&:debit_cents)).to eq(entry.lines.sum(&:credit_cents))

    debit  = entry.lines.find { |l| l.debit_cents.positive? }
    credit = entry.lines.find { |l| l.credit_cents.positive? }
    expect(debit.account_code).to eq(Accounting::JournalEntryService::ADVANCE_CODE)
    expect(credit.treasury_id).to eq(safe.id)
    expect(safe.reload.balance_cents).to eq(400_000)
  end

  it "keeps the payroll_advance kind, so the reports still recognise it" do
    advance = pay!
    voucher = advance.payment_allocations.sole.payment

    txn = TreasuryTransaction.find_by(source_record: voucher)
    expect(txn.kind).to eq("payroll_advance")
    expect(Accounting::CashFlowService::OPERATING_KINDS).to include("payroll_advance")
  end

  it "still lines up on the profit-to-cash bridge" do
    pay!(paid_on: Date.new(2026, 6, 15))

    bridge = Accounting::ProfitVsCashService.new(
      start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 30)
    )

    # Paid and charged in the same period, so the timing line nets to nothing
    # and nothing is left unexplained.
    expect(bridge.lines.map(&:key)).not_to include(:advance_timing)
    expect(bridge.residual_cents).to eq(0)
  end

  it "gives the money back when the advance is deleted" do
    advance = pay!
    voucher = advance.payment_allocations.sole.payment
    expect(safe.reload.balance_cents).to eq(400_000)

    advance.destroy!

    expect(Voucher.exists?(voucher.id)).to be(false)
    expect(safe.reload.balance_cents).to eq(500_000)
    expect(JournalEntry.where(source_record_type: "Voucher", source_record_id: voucher.id)).to be_empty
  end
end
