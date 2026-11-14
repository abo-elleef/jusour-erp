# frozen_string_literal: true

require "rails_helper"

RSpec.describe WholeSalesQuantity do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, unit: "kg") }
  let(:customer) { create(:customer, company: company, customer_type: "commercial") }

  before { Current.company = company }

  def invoice_with(qty, status: "draft")
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, location: location,
      invoice_date: Date.current, status: status)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: qty, unit: ingredient.unit,
      unit_price_cents: 1_000)
    inv
  end

  def credit_note_with(qty)
    note = CreditNote.new(company: company, customer: customer, user: user, location: location,
      credit_note_date: Date.current)
    note.credit_note_lines.build(ingredient: ingredient, quantity: qty, unit: ingredient.unit,
      unit_price_cents: 1_000)
    note
  end

  context "with the default setting (whole numbers only)" do
    it "accepts a whole quantity on an invoice" do
      expect(invoice_with(3)).to be_valid
    end

    it "rejects a fractional quantity on an invoice line" do
      line = invoice_with(2.5).customer_invoice_lines.first
      expect(line).not_to be_valid
      expect(line.errors.details[:quantity]).to include(error: :whole_number_required)
    end

    it "accepts 3.0 as a whole number" do
      expect(invoice_with(BigDecimal("3.000"))).to be_valid
    end

    it "rejects a fractional quantity on a return (credit note) line" do
      line = credit_note_with(1.5).credit_note_lines.first
      expect(line).not_to be_valid
      expect(line.errors.details[:quantity]).to include(error: :whole_number_required)
    end

    it "leaves historical (imported) invoices alone" do
      line = invoice_with(2.5, status: "historical").customer_invoice_lines.first
      line.valid?
      expect(line.errors.details[:quantity]).not_to include(error: :whole_number_required)
    end

    it "doesn't block saving a line whose old fractional quantity is unchanged" do
      Setting.set("allow_fractional_sales_quantities", true)
      inv = invoice_with(2.5)
      inv.save!
      Setting.set("allow_fractional_sales_quantities", false)

      line = inv.customer_invoice_lines.first.reload
      line.position = 2
      expect(line).to be_valid
    end
  end

  context "when the owner allows fractions" do
    before { Setting.set("allow_fractional_sales_quantities", true) }

    it "accepts a fractional quantity on invoices and returns" do
      expect(invoice_with(2.5)).to be_valid
      expect(credit_note_with(1.5).credit_note_lines.first).to be_valid
    end
  end
end
