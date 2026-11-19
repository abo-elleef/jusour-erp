# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerInvoiceLine do
  let(:company) { create(:company, business_type: "distribution") }
  let(:user) { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, unit: "kg",
      selling_price_cents: 2_000, cost_per_unit_cents: 1_500)
  end
  let(:customer) { create(:customer, company: company) }

  before { Current.company = company }

  def invoice(status: "draft")
    CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, status: status)
  end

  def line_on(inv, **attrs)
    inv.customer_invoice_lines.build({ ingredient: ingredient, quantity: 2, unit: "kg" }.merge(attrs))
  end

  describe "unit price" do
    it "starts at the product's selling price when left blank, and is not flagged" do
      inv = invoice
      line = line_on(inv, unit_price_pounds: "")
      inv.save!

      expect(line.reload.unit_price_cents).to eq(2_000)
      expect(line.list_price_cents).to eq(2_000)
      expect(line.price_overridden).to be(false)
    end

    it "saves a typed price and marks the line as changed" do
      inv = invoice
      line = line_on(inv, unit_price_pounds: "18.50")
      inv.save!

      expect(line.reload.unit_price_cents).to eq(1_850)
      expect(line.line_total_cents).to eq(3_700)
      expect(line.list_price_cents).to eq(2_000)
      expect(line.price_overridden).to be(true)
      expect(inv.reload.total_cents).to eq(3_700)
    end

    it "does not flag a typed price equal to the selling price" do
      inv = invoice
      line = line_on(inv, unit_price_pounds: "20")
      inv.save!

      expect(line.reload.price_overridden).to be(false)
    end

    it "clears the flag when the price is set back to the list price" do
      inv = invoice
      line = line_on(inv, unit_price_cents: 2_500)
      inv.save!
      expect(line.reload.price_overridden).to be(true)

      line.update!(unit_price_cents: 2_000)
      expect(line.reload.price_overridden).to be(false)
    end

    it "keeps the list price it was created with when the product's price later changes" do
      inv = invoice
      line = line_on(inv)
      inv.save!
      ingredient.update!(selling_price_cents: 3_000)

      line.reload.update!(quantity: 3)
      expect(line.reload.list_price_cents).to eq(2_000)
      expect(line.price_overridden).to be(false)
    end

    it "never flags lines that existed before list prices were recorded" do
      inv = invoice
      line = line_on(inv, unit_price_cents: 9_999)
      inv.save!
      line.update_columns(list_price_cents: nil, price_overridden: false) # an old row

      line.reload.update!(quantity: 4)
      expect(line.reload.price_overridden).to be(false)
    end

    it "never flags imported (historical) invoice lines" do
      inv = invoice(status: "historical")
      line = line_on(inv, unit_price_cents: 9_999)
      inv.save!

      expect(line.reload.price_overridden).to be(false)
      expect(line.list_price_cents).to be_nil
    end
  end

  describe "#below_cost?" do
    it "warns when the price is under the product's cost, and still saves" do
      inv = invoice
      line = line_on(inv, unit_price_cents: 1_200)
      expect(inv.save).to be(true)

      expect(line.reload).to be_below_cost
      expect(line.unit_cost_cents).to eq(1_500)
    end

    it "does not warn at or above cost" do
      line = line_on(invoice, unit_price_cents: 1_500)
      expect(line).not_to be_below_cost
    end

    it "does not warn when the product has no cost" do
      ingredient.update_columns(cost_per_unit_cents: 0)
      line = line_on(invoice, unit_price_cents: 1)
      expect(line).not_to be_below_cost
      expect(line.unit_cost_cents).to be_nil
    end
  end
end
