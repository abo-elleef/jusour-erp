# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customer AR flows (payments, opening balance, aging)", type: :model do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 0,
      opening_balance_cents: 0, company: company)
  end
  # No credit limits -> confirms never blocked.
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }

  before do
    Current.company = company
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 1000,
      quantity_remaining: 1000, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  def confirm_invoice!(total_cents:, date: Date.current)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user,
      location: location, invoice_date: date)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit,
      unit_price_cents: total_cents)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, user).call
    inv.reload
  end

  describe Sales::RecordCustomerPaymentService do
    it "settles AR, banks the cash, and allocates FIFO oldest-first" do
      a = confirm_invoice!(total_cents: 100_000, date: 20.days.ago.to_date)
      b = confirm_invoice!(total_cents: 60_000, date: 5.days.ago.to_date)
      expect(customer.reload.ar_balance_cents).to eq(160_000)

      described_class.new(customer: customer, treasury: cash, amount_cents: 120_000, user: user).call

      expect(customer.reload.ar_balance_cents).to eq(40_000)
      expect(cash.reload.balance_cents).to eq(120_000)
      expect(a.reload.payment_status).to eq("paid")            # 100k fully applied
      expect(b.reload.payment_status).to eq("partially_paid")  # 20k of 60k
      expect(b.balance_due_cents).to eq(40_000)
    end

    it "handles overpayment as an on-account credit (AR can go negative)" do
      confirm_invoice!(total_cents: 100_000)
      described_class.new(customer: customer, treasury: cash, amount_cents: 130_000, user: user).call
      expect(customer.reload.ar_balance_cents).to eq(-30_000)
    end

    it "rejects a non-positive amount" do
      expect {
        described_class.new(customer: customer, treasury: cash, amount_cents: 0, user: user).call
      }.to raise_error(Sales::RecordCustomerPaymentService::Error)
    end
  end

  describe "opening balance" do
    it "raises AR without recognizing revenue (Dr AR / Cr Equity)" do
      Accounting::CustomerArLedgerService.new(customer).open_balance!(
        amount_cents: 50_000, user: user, occurred_on: Date.current
      )
      expect(customer.reload.ar_balance_cents).to eq(50_000)

      entry = JournalEntry.where(company: company).order(:created_at).last
      expect(entry.lines.sum(&:debit_cents)).to eq(entry.lines.sum(&:credit_cents))
      equity = entry.lines.find { |l| l.account_code == Accounting::JournalEntryService::EQUITY_CODE }
      expect(equity.credit_cents).to eq(50_000)
    end
  end

  describe Sales::CustomerAgingService do
    it "buckets outstanding invoices by days past due" do
      customer.update!(credit_terms_days: 30)
      old_inv = confirm_invoice!(total_cents: 70_000, date: 100.days.ago.to_date) # due 70d ago -> 61-90
      new_inv = confirm_invoice!(total_cents: 20_000, date: 10.days.ago.to_date)  # due in 20d -> not_due

      result = described_class.new(customer, as_of: Date.current).call

      expect(result.buckets[:days_61_90]).to eq(70_000)
      expect(result.buckets[:not_due]).to eq(20_000)
      expect(result.total_cents).to eq(90_000)
      expect(result.ledger_balance_cents).to eq(90_000) # reconciles with the AR ledger
      expect(result.rows.map { |r| r.invoice.id }).to include(old_inv.id, new_inv.id)
    end

    it "drops fully-paid invoices from the aging" do
      confirm_invoice!(total_cents: 40_000, date: 5.days.ago.to_date)
      Sales::RecordCustomerPaymentService.new(customer: customer, treasury: cash, amount_cents: 40_000, user: user).call

      result = described_class.new(customer).call
      expect(result.total_cents).to eq(0)
      expect(result.rows).to be_empty
    end
  end
end
