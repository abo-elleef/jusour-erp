# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales::Reports", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:bond) do
    create(:ingredient, company: company, ingredient_category: category, name: "Bond Flipro", unit: "pieces")
  end
  let!(:kit) do
    create(:ingredient, company: company, ingredient_category: category, name: "Addition Kit", unit: "pieces")
  end
  let(:clinic) { create(:customer, company: company, name: "Dream Clinic", customer_type: "commercial") }

  before do
    Current.company = company
    sign_in owner
  end

  # Historical documents are imported sales that never touched the ledger or stock —
  # they still belong in a sales report.
  def historical_invoice(ingredient:, quantity:, price_cents:, date: Date.current)
    inv = CustomerInvoice.new(company: company, customer: clinic, user: owner,
      salesperson: owner, location: location, invoice_date: date)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: quantity,
      unit: ingredient.unit, unit_price_cents: price_cents)
    inv.save!
    inv.update_columns(status: "historical")
    inv
  end

  def historical_credit_note(ingredient:, quantity:, price_cents:, date: Date.current)
    note = CreditNote.new(company: company, customer: clinic, user: owner,
      location: location, credit_note_date: date, restock: false)
    note.credit_note_lines.build(ingredient: ingredient, quantity: quantity,
      unit: ingredient.unit, unit_price_cents: price_cents)
    note.save!
    note.update_columns(status: "historical")
    note
  end

  def report(from: 30.days.ago.to_date, to: Date.current)
    ::Sales::SalesReportService.new(from, to).call
  end

  describe "the page" do
    it "renders" do
      historical_invoice(ingredient: bond, quantity: 10, price_cents: 2_000)

      get admin_sales_reports_path(locale: "en")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bond Flipro")
      expect(response.body).to include("Dream Clinic")
    end

    it "says so when the period is empty rather than rendering blank tables" do
      get admin_sales_reports_path(locale: "en", start_date: "2020-01-01", end_date: "2020-01-31")
      expect(response.body).to include(I18n.t("sales.reports.empty_title", locale: "en"))
    end

    it "is unavailable to a company without credit sales" do
      company.update!(business_type: "restaurant", feature_overrides: {})

      get admin_sales_reports_path
      expect(response).to redirect_to(admin_root_path)
    end
  end

  describe "the numbers" do
    it "counts historical and confirmed sales alike, and drafts not at all" do
      historical_invoice(ingredient: bond, quantity: 10, price_cents: 2_000) # 200.00
      CustomerInvoice.new(company: company, customer: clinic, user: owner, location: location,
        invoice_date: Date.current).tap { |i|
          i.customer_invoice_lines.build(ingredient: bond, quantity: 5, unit: bond.unit, unit_price_cents: 2_000)
          i.save!
        } # a draft — 100.00, must not count

      expect(report[:summary][:gross_sales_cents]).to eq(20_000)
      expect(report[:summary][:invoice_count]).to eq(1)
    end

    it "nets returns off the totals and off the product that came back" do
      historical_invoice(ingredient: bond, quantity: 10, price_cents: 2_000)  # 200.00
      historical_credit_note(ingredient: bond, quantity: 2, price_cents: 2_000) # 40.00 back

      summary = report[:summary]
      expect(summary[:gross_sales_cents]).to eq(20_000)
      expect(summary[:returns_cents]).to eq(4_000)
      expect(summary[:net_sales_cents]).to eq(16_000)

      row = report[:by_product].find { |r| r.name == "Bond Flipro" }
      expect(row.units).to eq(8)
      expect(row.net_cents).to eq(16_000)
    end

    it "lists a product that was only returned in the period" do
      historical_invoice(ingredient: bond, quantity: 1, price_cents: 2_000)
      historical_credit_note(ingredient: kit, quantity: 3, price_cents: 1_000)

      row = report[:by_product].find { |r| r.name == "Addition Kit" }
      expect(row).to be_present
      expect(row.units).to eq(-3)
      expect(row.net_cents).to eq(-3_000)
    end

    it "ranks products by net revenue" do
      historical_invoice(ingredient: bond, quantity: 1, price_cents: 1_000)
      historical_invoice(ingredient: kit, quantity: 1, price_cents: 9_000)

      expect(report[:by_product].map(&:name)).to eq(["Addition Kit", "Bond Flipro"])
    end

    it "groups by customer and by salesperson" do
      other = create(:user, company: company, name: "Rep Two", role: "cashier")
      historical_invoice(ingredient: bond, quantity: 1, price_cents: 5_000)
      inv = historical_invoice(ingredient: kit, quantity: 1, price_cents: 3_000)
      inv.update_columns(salesperson_id: other.id)

      expect(report[:by_customer].map { |r| [r.name, r.units, r.net_cents] })
        .to eq([["Dream Clinic", 2, 8_000]])
      expect(report[:by_salesperson].map { |r| [r.name, r.revenue_cents] })
        .to eq([[owner.name, 5_000], ["Rep Two", 3_000]])
    end

    it "excludes anything outside the date range" do
      historical_invoice(ingredient: bond, quantity: 1, price_cents: 5_000, date: 90.days.ago.to_date)

      expect(report[:summary][:invoice_count]).to eq(0)
      expect(report(from: 100.days.ago.to_date)[:summary][:invoice_count]).to eq(1)
    end

    it "reports only days that saw activity" do
      historical_invoice(ingredient: bond, quantity: 1, price_cents: 5_000, date: Date.current)
      historical_invoice(ingredient: kit, quantity: 1, price_cents: 5_000, date: 2.days.ago.to_date)

      expect(report[:daily].map { |d| d[:date] }).to eq([2.days.ago.to_date, Date.current])
      expect(report[:daily].sum { |d| d[:net_cents] }).to eq(10_000)
    end
  end
end
