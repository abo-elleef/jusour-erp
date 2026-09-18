# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "vouchers:backfill" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  let(:task) { Rake::Task["vouchers:backfill"] }

  before { task.reenable }

  let(:company) { create(:company) }
  let(:user)    { create(:user, company: company) }
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 100_000,
                     opening_balance_cents: 100_000, company: company)
  end
  let(:category) do
    ExpenseCategory.create!(name: "Rent", category_type: "rent", position: 1, company: company)
  end

  before { Current.company = company }

  # An expense as it looked before the switch: it moved its own cash, and no
  # voucher ever existed for it.
  def legacy_expense!(amount_cents:, date: Date.current)
    expense = Expense.create!(expense_category: category, user: user, company: company,
                              treasury: cash, description: "Old rent",
                              amount_cents: amount_cents, expense_date: date)
    expense.payment_allocations.each { |a| a.delete }
    Voucher.delete_all
    expense
  end

  it "issues a payment voucher for a historical expense, dated the same day" do
    expense = legacy_expense!(amount_cents: 20_000, date: Date.new(2026, 3, 4))

    task.invoke("commit")

    voucher = Voucher.sole
    expect(voucher.direction).to eq(Voucher::PAYMENT)
    expect(voucher.voucher_date).to eq(Date.new(2026, 3, 4))
    expect(voucher.amount_cents).to eq(20_000)
    expect(voucher.payment_allocations.sole.settles).to eq(expense)
  end

  it "posts nothing, so no figure moves" do
    legacy_expense!(amount_cents: 20_000)
    balance_before = cash.reload.balance_cents
    entries_before = JournalEntry.count
    txns_before = TreasuryTransaction.count

    task.invoke("commit")

    expect(cash.reload.balance_cents).to eq(balance_before)
    expect(JournalEntry.count).to eq(entries_before)
    expect(TreasuryTransaction.count).to eq(txns_before)
    expect(Voucher.sole).to be_backfilled
  end

  it "writes nothing on a dry run" do
    legacy_expense!(amount_cents: 20_000)

    task.invoke

    expect(Voucher.count).to eq(0)
  end

  it "can be run twice" do
    legacy_expense!(amount_cents: 20_000)

    task.invoke("commit")
    task.reenable

    expect { task.invoke("commit") }.not_to change(Voucher, :count)
  end

  it "leaves an expense that already has its voucher alone" do
    Expense.create!(expense_category: category, user: user, company: company,
                    treasury: cash, description: "New rent",
                    amount_cents: 5_000, expense_date: Date.current)
    expect(Voucher.count).to eq(1)

    task.invoke("commit")

    expect(Voucher.count).to eq(1)
    expect(Voucher.sole).not_to be_backfilled
  end

  it "skips an expense on account, which has no cash to document" do
    Expense.create!(expense_category: category, user: user, company: company,
                    description: "Unpaid rent", amount_cents: 7_000,
                    expense_date: Date.current)

    task.invoke("commit")

    expect(Voucher.count).to eq(0)
  end

  it "issues a receipt voucher for historical income" do
    income_category = IncomeCategory.create!(name: "Catering", category_type: "catering",
                                             position: 1, company: company)
    income = Income.create!(income_category: income_category, user: user, company: company,
                            treasury: cash, description: "Old catering",
                            amount_cents: 15_000, income_date: Date.new(2026, 2, 1))
    income.payment_allocations.each { |a| a.delete }
    Voucher.delete_all

    task.invoke("commit")

    voucher = Voucher.sole
    expect(voucher.direction).to eq(Voucher::RECEIPT)
    expect(voucher.amount_cents).to eq(15_000)
    expect(voucher.voucher_date).to eq(Date.new(2026, 2, 1))
  end
end
