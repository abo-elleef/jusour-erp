# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerInvoice do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "regular") }
  let(:shipping_company) { create(:shipping_company, company: company) }

  before { Current.company = company }

  def build_invoice(**attrs)
    inv = described_class.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, payment_method: "cash", **attrs)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv
  end

  it "folds the delivery fee actually charged into the total" do
    inv = build_invoice(fulfillment_method: "delivery", shipping_company: shipping_company,
      standard_delivery_fee_cents: 10_000, delivery_fee_cents: 10_000)
    inv.save!

    expect(inv.total_cents).to eq(110_000)
  end

  it "still totals goods only when a free-delivery promo waives the fee" do
    inv = build_invoice(fulfillment_method: "delivery", shipping_company: shipping_company,
      standard_delivery_fee_cents: 10_000, delivery_fee_cents: 0)
    inv.save!

    expect(inv.total_cents).to eq(100_000)
    expect(inv.waived_delivery_fee_cents).to eq(10_000)
  end

  it "zeroes both delivery-fee fields for a pickup invoice" do
    inv = build_invoice(fulfillment_method: "pickup", standard_delivery_fee_cents: 10_000, delivery_fee_cents: 10_000)
    inv.save!

    expect(inv.standard_delivery_fee_cents).to eq(0)
    expect(inv.delivery_fee_cents).to eq(0)
    expect(inv.total_cents).to eq(100_000)
  end

  it "rejects a delivery fee charged above the standard fee" do
    inv = build_invoice(fulfillment_method: "delivery", shipping_company: shipping_company,
      standard_delivery_fee_cents: 10_000, delivery_fee_cents: 15_000)

    expect(inv).not_to be_valid
    expect(inv.errors[:delivery_fee_cents]).to be_present
  end

  it "accepts pound-denominated input through the money_input virtual attributes" do
    inv = build_invoice(fulfillment_method: "delivery", shipping_company: shipping_company)
    inv.standard_delivery_fee_pounds = "100.50"
    inv.delivery_fee_pounds = "100.50"
    inv.save!

    expect(inv.standard_delivery_fee_cents).to eq(10_050)
    expect(inv.delivery_fee_cents).to eq(10_050)
  end

  it "treats a blank delivery-fee-charged input (the free-delivery promo path in the form) as 0, not invalid" do
    inv = build_invoice(fulfillment_method: "delivery", shipping_company: shipping_company)
    inv.standard_delivery_fee_pounds = "100"
    inv.delivery_fee_pounds = ""
    inv.save!

    expect(inv.delivery_fee_cents).to eq(0)
    expect(inv.standard_delivery_fee_cents).to eq(10_000)
    expect(inv.total_cents).to eq(100_000)
  end
end
