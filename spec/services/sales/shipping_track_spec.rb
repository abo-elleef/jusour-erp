# frozen_string_literal: true

require "rails_helper"

# A delivery's shipping track: waiting_for_shipping (on confirm) → shipped (at
# dispatch) → shipping_completed (courier's system shows it delivered).
RSpec.describe "Customer invoice shipping track" do
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

  def invoice(payment_method: "cash_on_delivery", fulfillment_method: "delivery", **attrs)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, payment_method: payment_method, fulfillment_method: fulfillment_method,
      shipping_company: (fulfillment_method == "delivery" ? shipping_company : nil), **attrs)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv.save!
    inv
  end

  def confirm(inv) = Sales::ConfirmCustomerInvoiceService.new(inv, user).call

  it "has no track while a draft" do
    expect(invoice.shipping_status).to be_nil
  end

  it "starts waiting for shipping when a delivery is confirmed" do
    inv = invoice
    confirm(inv)
    expect(inv.reload.shipping_status).to eq("waiting_for_shipping")
  end

  it "starts the track on every confirm path (cash delivery too)" do
    inv = invoice(payment_method: "cash")
    confirm(inv)
    expect(inv.reload.shipping_status).to eq("waiting_for_shipping")
  end

  it "starts the track only once an online delivery payment is approved" do
    treasury = Treasury.create!(name: "Bank", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
    inv = invoice(payment_method: "online", sales_payment_method: create(:sales_payment_method, company: company, treasury: treasury))

    confirm(inv) # -> pending approval
    expect(inv.reload.shipping_status).to be_nil

    confirm(inv) # -> approved
    expect(inv.reload.shipping_status).to eq("waiting_for_shipping")
  end

  it "never gives a pickup invoice a track" do
    inv = invoice(payment_method: "cash", fulfillment_method: "pickup")
    confirm(inv)
    expect(inv.reload.shipping_status).to be_nil
  end

  it "moves to shipped at dispatch" do
    inv = invoice
    confirm(inv)
    Sales::DispatchCustomerInvoiceService.new(inv, user).call
    expect(inv.reload.shipping_status).to eq("shipped")
  end

  describe Sales::CompleteShippingService do
    let(:checker) { create(:user, company: company, name: "Courier checker") }

    it "marks a shipped invoice delivered, with who and when, and moves no money" do
      inv = invoice
      confirm(inv)
      Sales::DispatchCustomerInvoiceService.new(inv, user).call
      balance_before = shipping_company.reload.balance_cents

      expect { described_class.new(inv, checker).call }
        .not_to(change { [JournalEntry.count, TreasuryTransaction.count] })

      inv.reload
      expect(inv.shipping_status).to eq("shipping_completed")
      expect(inv.shipping_completed_by).to eq(checker)
      expect(inv.shipping_completed_at).to be_present
      expect(shipping_company.reload.balance_cents).to eq(balance_before)
    end

    it "refuses an invoice that hasn't been handed to the courier" do
      inv = invoice
      confirm(inv)
      expect { described_class.new(inv, checker).call }.to raise_error(described_class::Error)
      expect(inv.reload.shipping_status).to eq("waiting_for_shipping")
    end

    it "refuses to complete twice" do
      inv = invoice
      confirm(inv)
      Sales::DispatchCustomerInvoiceService.new(inv, user).call
      described_class.new(inv, checker).call
      expect { described_class.new(inv, checker).call }.to raise_error(described_class::Error)
    end
  end
end
