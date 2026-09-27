# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sales::ConfirmCreditNoteService do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }

  before do
    Current.company = company
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 1000,
      quantity_remaining: 1000, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  def confirm_invoice!(total_cents:, date: Date.current)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location, invoice_date: date)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: total_cents)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, user).call
    inv.reload
  end

  def draft_credit_note(qty:, price_cents:, restock: true, invoice: nil)
    cn = CreditNote.new(company: company, customer: customer, user: user, location: location,
      credit_note_date: Date.current, restock: restock, customer_invoice: invoice)
    cn.credit_note_lines.build(ingredient: ingredient, quantity: qty, unit: ingredient.unit, unit_price_cents: price_cents)
    cn.save!
    cn
  end

  it "reduces AR and posts a balanced Dr Revenue / Cr AR entry" do
    confirm_invoice!(total_cents: 100_000)
    expect(customer.reload.ar_balance_cents).to eq(100_000)

    cn = draft_credit_note(qty: 2, price_cents: 20_000) # 40,000
    described_class.new(cn, user).call

    expect(cn.reload.status).to eq("confirmed")
    expect(customer.reload.ar_balance_cents).to eq(60_000)
    expect(customer.total_spent_cents).to eq(60_000) # 100,000 invoice less the 40,000 return

    entry = JournalEntry.where(company: company).order(:created_at).last
    expect(entry.lines.sum(&:debit_cents)).to eq(entry.lines.sum(&:credit_cents))
    rev = entry.lines.find { |l| l.account_code == Accounting::JournalEntryService::SALES_REVENUE_CODE }
    expect(rev.debit_cents).to eq(40_000)
  end

  it "returns the goods to stock when restock is on" do
    confirm_invoice!(total_cents: 100_000)
    before = ingredient.stock_batches.where(location: location).sum(:quantity_remaining).to_d

    cn = draft_credit_note(qty: 3, price_cents: 20_000, restock: true)
    described_class.new(cn, user).call

    after = ingredient.stock_batches.where(location: location).sum(:quantity_remaining).to_d
    expect(after - before).to eq(3)
    adj = StockAdjustment.find_by(adjustment_type: "customer_return")
    expect(adj.quantity_delta.to_d).to eq(3)
  end

  it "does not touch stock when restock is off" do
    confirm_invoice!(total_cents: 100_000)
    before = ingredient.stock_batches.where(location: location).sum(:quantity_remaining).to_d

    cn = draft_credit_note(qty: 3, price_cents: 20_000, restock: false)
    described_class.new(cn, user).call

    after = ingredient.stock_batches.where(location: location).sum(:quantity_remaining).to_d
    expect(after).to eq(before)
    expect(StockAdjustment.where(adjustment_type: "customer_return")).to be_empty
  end

  it "applies the credit against a linked invoice's balance" do
    inv = confirm_invoice!(total_cents: 100_000)

    cn = draft_credit_note(qty: 2, price_cents: 20_000, invoice: inv) # 40,000
    described_class.new(cn, user).call

    expect(inv.reload.balance_due_cents).to eq(60_000)
    expect(inv.payment_status).to eq("partially_paid")
    expect(customer.reload.ar_balance_cents).to eq(60_000)
  end

  it "rejects confirming a non-draft or empty credit note" do
    confirm_invoice!(total_cents: 100_000)
    cn = draft_credit_note(qty: 1, price_cents: 10_000)
    described_class.new(cn, user).call
    expect { described_class.new(cn, user).call }.to raise_error(Sales::ConfirmCreditNoteService::Error)
  end
end
