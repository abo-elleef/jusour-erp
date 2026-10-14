# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sales::SalesReportService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, unit: "kg") }

  let(:doctor) { create(:customer, company: company, name: "Dr. Amr", customer_type: "regular") }
  let(:clinic) { create(:customer, company: company, name: "Bazzar Clinic", customer_type: "commercial") }
  let(:shipping_company) { create(:shipping_company, company: company) }

  before { Current.company = company }

  def invoice_for(customer, total_cents:)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, status: "historical")
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit,
      unit_price_cents: total_cents)
    inv.save!
    inv
  end

  def report(customer_type: nil)
    described_class.new(Date.current, Date.current, customer_type: customer_type).call
  end

  it "reads every customer when no customer_type is given" do
    invoice_for(doctor, total_cents: 5_000)
    invoice_for(clinic, total_cents: 50_000)

    result = report
    expect(result[:by_customer].map(&:name)).to contain_exactly("Dr. Amr", "Bazzar Clinic")
    expect(result[:summary][:net_sales_cents]).to eq(55_000)
  end

  it "narrows every breakdown to commercial customers only" do
    invoice_for(doctor, total_cents: 5_000)
    invoice_for(clinic, total_cents: 50_000)

    result = report(customer_type: "commercial")
    expect(result[:by_customer].map(&:name)).to eq(["Bazzar Clinic"])
    expect(result[:summary][:net_sales_cents]).to eq(50_000)
  end

  it "narrows every breakdown to regular customers only, so a commercial buyer can't bury them" do
    invoice_for(doctor, total_cents: 5_000)
    invoice_for(clinic, total_cents: 50_000)

    result = report(customer_type: "regular")
    expect(result[:by_customer].map(&:name)).to eq(["Dr. Amr"])
    expect(result[:summary][:net_sales_cents]).to eq(5_000)
  end

  it "ignores an unrecognized customer_type rather than raising" do
    invoice_for(doctor, total_cents: 5_000)

    result = report(customer_type: "bogus")
    expect(result[:by_customer].map(&:name)).to eq(["Dr. Amr"])
  end

  it "totals the delivery fee waived by free-delivery promos, across delivery invoices only" do
    inv = CustomerInvoice.new(company: company, customer: doctor, user: user, location: location,
      invoice_date: Date.current, status: "historical", fulfillment_method: "delivery",
      shipping_company: shipping_company, standard_delivery_fee_cents: 10_000, delivery_fee_cents: 0)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 5_000)
    inv.save!
    invoice_for(clinic, total_cents: 50_000) # pickup — never contributes

    expect(report[:summary][:forgone_delivery_fee_cents]).to eq(10_000)
  end
end
