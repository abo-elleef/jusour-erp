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

  # The reported bug: a payment voucher naming a vendor as its party, with
  # nothing specifically settled, posted the right journal entry but left the
  # supplier's AP treasury balance untouched — the number the accountant
  # actually reads never moved.
  it "moves a supplier's AP balance when named as a voucher's party with nothing settled" do
    supplier = Supplier.create!(name: "On Account Vendor", lead_time_days: 1, company: company)
    expect(supplier.ap_balance_cents).to eq(0)

    voucher = Accounting::RecordVoucherService.new(
      direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 15_000,
      party_type: "Supplier", party_id: supplier.id
    ).call

    expect(voucher).to be_a(Voucher)
    expect(supplier.reload.ap_balance_cents).to eq(-15_000)
    expect(cash.reload.balance_cents).to eq(85_000)
  end

  it "moves a customer's AR balance when named as a voucher's party with nothing settled" do
    customer = create(:customer, company: company, name: "On Account Customer")

    voucher = Accounting::RecordVoucherService.new(
      direction: Voucher::RECEIPT, treasury: cash, user: user, amount_cents: 20_000,
      party_type: "Customer", party_id: customer.id
    ).call

    expect(voucher).to be_a(Voucher)
    expect(customer.reload.ar_balance_cents).to eq(-20_000)
    expect(cash.reload.balance_cents).to eq(120_000)
  end

  # The party picker allows either direction against either party — a payment
  # voucher can be "paid to" a commercial customer (refunding a credit
  # balance). That leg grows the receivable rather than shrinking it, the
  # opposite sign from the receipt case above, because the journal entry
  # debits the customer's AR account on a payment voucher. The treasury cache
  # has to flip the same way or it drifts out of step again.
  it "moves a customer's AR balance the opposite way on a refund payment voucher" do
    customer = create(:customer, company: company, name: "Credit Customer")
    Accounting::RecordVoucherService.new(
      direction: Voucher::RECEIPT, treasury: cash, user: user, amount_cents: 20_000,
      party_type: "Customer", party_id: customer.id
    ).call
    expect(customer.reload.ar_balance_cents).to eq(-20_000)

    voucher = Accounting::RecordVoucherService.new(
      direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 5_000,
      party_type: "Customer", party_id: customer.id
    ).call

    expect(voucher).to be_a(Voucher)
    expect(customer.reload.ar_balance_cents).to eq(-15_000)
    expect(cash.reload.balance_cents).to eq(115_000)
  end

  # Mirror case on the supplier side: a receipt voucher "received from" a
  # vendor (a rebate) grows the AP balance instead of shrinking it.
  it "moves a supplier's AP balance the opposite way on a rebate receipt voucher" do
    supplier = Supplier.create!(name: "Rebate Vendor", lead_time_days: 1, company: company)
    Accounting::RecordVoucherService.new(
      direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 15_000,
      party_type: "Supplier", party_id: supplier.id
    ).call
    expect(supplier.reload.ap_balance_cents).to eq(-15_000)

    voucher = Accounting::RecordVoucherService.new(
      direction: Voucher::RECEIPT, treasury: cash, user: user, amount_cents: 4_000,
      party_type: "Supplier", party_id: supplier.id
    ).call

    expect(voucher).to be_a(Voucher)
    expect(supplier.reload.ap_balance_cents).to eq(-11_000)
    expect(cash.reload.balance_cents).to eq(89_000)
  end
end
