# frozen_string_literal: true

require "rails_helper"

# A customer's receivable and a supplier's payable are treasuries created on
# demand, so a customer who has never bought on credit has none. The ledger
# services that vouchers replaced ensured one before posting; reading the
# association straight meant the first payment from such a customer raised
# NoMethodError on nil.
RSpec.describe "A voucher for a counterparty with no ledger treasury yet" do
  let(:company) { Current.company }
  let(:user)    { create(:user) }
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 100_000,
                     opening_balance_cents: 100_000, company: company)
  end

  it "takes a payment from a customer who has never bought on credit" do
    customer = create(:customer, company: company, name: "Walk-in")
    expect(customer.ar_treasury).to be_nil

    voucher = Sales::RecordCustomerPaymentService.new(
      customer: customer, treasury: cash, amount_cents: 20_000, user: user
    ).call

    expect(voucher).to be_a(Voucher)
    expect(customer.reload.ar_treasury).to be_present
    expect(customer.ar_balance_cents).to eq(-20_000)
    expect(cash.reload.balance_cents).to eq(120_000)
  end

  # A supplier gets its payable on create, unlike a customer, so this is the
  # safe side — kept because the voucher still has to resolve it, and a change
  # to how suppliers are made would surface here.
  it "pays a supplier that has never been invoiced" do
    supplier = Supplier.create!(name: "Brand New", lead_time_days: 1, company: company)

    voucher = Accounting::RecordVoucherService.new(
      direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 15_000,
      allocations: [{ settles: supplier, amount_cents: 15_000 }]
    ).call

    expect(voucher).to be_a(Voucher)
    expect(supplier.reload.ap_treasury).to be_present
    expect(cash.reload.balance_cents).to eq(85_000)
  end

  it "posts a balanced entry either way" do
    customer = create(:customer, company: company, name: "Walk-in")
    voucher = Sales::RecordCustomerPaymentService.new(
      customer: customer, treasury: cash, amount_cents: 20_000, user: user
    ).call

    entry = JournalEntry.for_source(voucher).sole
    expect(entry.lines.sum(&:debit_cents)).to eq(entry.lines.sum(&:credit_cents))
  end
end
