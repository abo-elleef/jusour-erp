# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sales::DispatchCustomerInvoiceService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "regular") }
  let(:shipping_company) { create(:shipping_company, company: company) }

  before do
    Current.company = company
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 100,
      quantity_remaining: 100, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  def cod_invoice(confirmed: true)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, payment_method: "cash_on_delivery", fulfillment_method: "delivery",
      shipping_company: shipping_company)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, user).call if confirmed
    inv
  end

  it "charges the shipping company and marks the invoice paid" do
    inv = cod_invoice

    described_class.new(inv, user).call

    expect(inv.reload.dispatched_at).to be_present
    expect(inv.payment_status).to eq("paid")
    expect(inv.amount_paid_cents).to eq(100_000)
    expect(shipping_company.reload.balance_cents).to eq(100_000)

    entry = JournalEntry.where(company: company).order(:created_at).last
    expect(entry.lines.sum(&:debit_cents)).to eq(entry.lines.sum(&:credit_cents))
  end

  it "is a pure fulfillment stamp for a delivery that already settled online — the shipping company is untouched" do
    treasury = Treasury.create!(name: "Bank", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
    payment_method = create(:sales_payment_method, company: company, treasury: treasury)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, payment_method: "online", fulfillment_method: "delivery",
      shipping_company: shipping_company, sales_payment_method: payment_method)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, user).call # pending
    Sales::ConfirmCustomerInvoiceService.new(inv, user).call # approve/settle

    described_class.new(inv, user).call

    expect(inv.reload.dispatched_at).to be_present
    expect(shipping_company.reload.balance_cents).to eq(0)
  end

  it "accrues the courier's standard delivery fee on top of the COD charge, netting to goods revenue only" do
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, payment_method: "cash_on_delivery", fulfillment_method: "delivery",
      shipping_company: shipping_company, standard_delivery_fee_cents: 10_000, delivery_fee_cents: 0)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, user).call

    described_class.new(inv, user).call

    # total_cents = subtotal (100_000) + delivery_fee_cents (0, waived) = 100_000
    expect(inv.reload.total_cents).to eq(100_000)
    expect(inv.amount_paid_cents).to eq(100_000)
    # courier collected 100_000 on delivery, but is owed 10_000 for their standard
    # fee cut — net balance is goods revenue only.
    expect(shipping_company.reload.balance_cents).to eq(90_000)
  end

  it "accrues the courier's standard delivery fee for an online sale even though the shipping company never touches the cash" do
    treasury = Treasury.create!(name: "Bank", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
    payment_method = create(:sales_payment_method, company: company, treasury: treasury)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, payment_method: "online", fulfillment_method: "delivery",
      shipping_company: shipping_company, sales_payment_method: payment_method,
      standard_delivery_fee_cents: 10_000, delivery_fee_cents: 10_000)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, user).call # pending
    Sales::ConfirmCustomerInvoiceService.new(inv, user).call # approve/settle

    described_class.new(inv, user).call

    # Nothing was collected on delivery, but the courier is still owed their fee outright.
    expect(shipping_company.reload.balance_cents).to eq(-10_000)
  end

  it "refuses to dispatch a draft, a pickup invoice, one with no shipping company, or an already-dispatched one" do
    draft = cod_invoice(confirmed: false)
    expect { described_class.new(draft, user).call }.to raise_error(described_class::Error)

    pickup = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, payment_method: "cash")
    pickup.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 20_000)
    pickup.save!
    Sales::ConfirmCustomerInvoiceService.new(pickup, user).call
    expect { described_class.new(pickup, user).call }.to raise_error(described_class::Error)

    inv = cod_invoice
    described_class.new(inv, user).call
    expect { described_class.new(inv, user).call }.to raise_error(described_class::Error)
  end
end
