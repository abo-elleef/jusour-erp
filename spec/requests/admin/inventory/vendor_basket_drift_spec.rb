# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Vendor basket drift report", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:other_category) { create(:ingredient_category, company: company, name: "Dry goods") }
  let(:acme) { Supplier.create!(name: "Acme Foods", company: company) }
  let(:zesty) { Supplier.create!(name: "Zesty Supply", company: company) }

  # This month vs the month before, which is what the service derives.
  let(:now_start) { Date.new(2026, 8, 1) }
  let(:now_end) { Date.new(2026, 8, 31) }

  def ingredient(name, unit: "kg", cat: category)
    create(:ingredient, company: company, ingredient_category: cat, name: name, unit: unit)
  end

  def invoice(on:, supplier: acme, draft: false, lines: {})
    inv = VendorInvoice.create!(supplier: supplier, user: owner, location: kitchen,
      invoice_number: "INV-#{SecureRandom.hex(4)}", invoice_date: on, received_on: on,
      draft: draft, company: company)
    lines.each do |ing, (qty, total_cents)|
      VendorInvoiceLine.create!(vendor_invoice: inv, ingredient: ing, quantity: qty,
        line_total_cents: total_cents, unit: ing.unit)
    end
    inv
  end

  def basket(**params)
    get admin_inventory_reports_vendor_basket_path(
      { start_date: now_start, end_date: now_end }.merge(params)
    )
    @request.env["action_controller.instance"].instance_variable_get(:@basket)
  end

  def row_for(result, name)
    result.rows.find { |row| row.ingredient.name == name }
  end

  before { sign_in owner }

  describe "the comparison window" do
    it "compares against the same length immediately before" do
      result = basket(start_date: Date.new(2026, 8, 20), end_date: Date.new(2026, 8, 31))

      # 12 days, so the prior window is the 12 days before it — not a whole month.
      expect(result.prior_end_date).to eq(Date.new(2026, 8, 19))
      expect(result.prior_start_date).to eq(Date.new(2026, 8, 8))
    end
  end

  describe "what counts as a purchase" do
    it "ignores draft invoices" do
      tomatoes = ingredient("Tomatoes")
      invoice(on: now_start + 1, lines: { tomatoes => [10, 10_000] })
      invoice(on: now_start + 2, draft: true, lines: { tomatoes => [10, 90_000] })

      result = basket

      expect(result.spend_cents).to eq(10_000)
      expect(result.invoice_count).to eq(1)
    end

    it "narrows by vendor and by category" do
      tomatoes = ingredient("Tomatoes")
      flour = ingredient("Flour", cat: other_category)
      invoice(on: now_start + 1, supplier: acme, lines: { tomatoes => [10, 10_000] })
      invoice(on: now_start + 1, supplier: zesty, lines: { flour => [5, 5_000] })

      expect(basket(supplier_id: zesty.id).rows.map { |r| r.ingredient.name }).to eq(["Flour"])
      expect(basket(category_id: other_category.id).rows.map { |r| r.ingredient.name }).to eq(["Flour"])
    end
  end

  describe "prices" do
    it "weights the period price by quantity, not by line count" do
      tomatoes = ingredient("Tomatoes")
      # 100 units at 10.00 and 1 unit at 1.00 — a plain mean would say 5.50.
      invoice(on: now_start + 1, lines: { tomatoes => [100, 100_000] })
      invoice(on: now_start + 2, lines: { tomatoes => [1, 100] })

      row = row_for(basket, "Tomatoes")

      expect(row.quantity).to eq(101)
      expect(row.spend_cents).to eq(100_100)
      expect(row.price_cents.round).to eq(991)
    end

    it "reports the change and what it cost" do
      tomatoes = ingredient("Tomatoes")
      invoice(on: now_start - 10, lines: { tomatoes => [100, 100_000] })  # 1000/unit
      invoice(on: now_start + 1, lines: { tomatoes => [80, 96_000] })     # 1200/unit

      row = row_for(basket, "Tomatoes")

      expect(row.prior_price_cents.round).to eq(1_000)
      expect(row.price_cents.round).to eq(1_200)
      expect(row.price_change_pct).to eq(20.0)
      # Last period's quantity at the new price: 100 × 200.
      expect(row.price_impact_cents).to eq(20_000)
    end
  end

  describe "splitting price from buying mix" do
    it "always adds up to the change it explains" do
      tomatoes = ingredient("Tomatoes")
      onions = ingredient("Onions")
      invoice(on: now_start - 10, lines: { tomatoes => [100, 100_000], onions => [50, 25_000] })
      invoice(on: now_start + 1, lines: { tomatoes => [120, 144_000], onions => [10, 5_500] })

      result = basket

      expect(result.price_effect_cents + result.mix_effect_cents).to eq(result.spend_change_cents)
    end

    it "calls a newly bought item mix, not inflation" do
      tomatoes = ingredient("Tomatoes")
      invoice(on: now_start - 10, lines: { tomatoes => [10, 10_000] })
      new_item = ingredient("Saffron")
      invoice(on: now_start + 1, lines: { tomatoes => [10, 10_000], new_item => [1, 50_000] })

      result = basket
      row = row_for(result, "Saffron")

      expect(row.price_impact_cents).to eq(0)
      expect(result.price_effect_cents).to eq(0)
      expect(result.mix_effect_cents).to eq(50_000)
    end

    it "calls a dropped item mix too, and credits back its whole spend" do
      tomatoes = ingredient("Tomatoes")
      dropped = ingredient("Truffle")
      invoice(on: now_start - 10, lines: { tomatoes => [10, 10_000], dropped => [2, 40_000] })
      invoice(on: now_start + 1, lines: { tomatoes => [10, 10_000] })

      result = basket
      row = row_for(result, "Truffle")

      expect(row.price_impact_cents).to eq(0)
      expect(result.mix_effect_cents).to eq(-40_000)
    end
  end

  describe "guarding against bad data" do
    # Found in real data: one line billed 12 units at ج.م.122,334 and made an
    # ingredient look 4,576% more expensive.
    it "flags an implausible move without dropping it from the totals" do
      tomatoes = ingredient("Tomatoes")
      invoice(on: now_start - 10, lines: { tomatoes => [100, 100_000] })
      invoice(on: now_start + 1, lines: { tomatoes => [12, 12_233_400] })

      result = basket
      row = row_for(result, "Tomatoes")

      expect(row).to be_suspicious
      expect(result.suspicious_rows).to include(row)
      # Still counted: the money really was spent.
      expect(result.spend_cents).to eq(12_233_400)
    end

    it "leaves a believable move unflagged" do
      tomatoes = ingredient("Tomatoes")
      invoice(on: now_start - 10, lines: { tomatoes => [100, 100_000] })
      invoice(on: now_start + 1, lines: { tomatoes => [100, 130_000] })

      row = row_for(basket, "Tomatoes")

      expect(row.price_change_pct).to eq(30.0)
      expect(row).not_to be_suspicious
    end
  end

  describe "the page" do
    it "ranks by price impact rather than percentage" do
      staple = ingredient("Flour")
      rare = ingredient("Saffron")
      invoice(on: now_start - 10, lines: { staple => [1000, 100_000], rare => [1, 10_000] })
      # Flour +10% on a big volume; saffron +80% on one unit.
      invoice(on: now_start + 1, lines: { staple => [1000, 110_000], rare => [1, 18_000] })

      result = basket

      expect(result.rows.first.ingredient.name).to eq("Flour")
      expect(row_for(result, "Saffron").price_change_pct).to be > row_for(result, "Flour").price_change_pct
    end

    it "renders the split, the table and the verify warning" do
      tomatoes = ingredient("Tomatoes")
      invoice(on: now_start - 10, lines: { tomatoes => [100, 100_000] })
      invoice(on: now_start + 1, lines: { tomatoes => [12, 12_233_400] })

      get admin_inventory_reports_vendor_basket_path(start_date: now_start, end_date: now_end)

      expect(response.body).to include(I18n.t("inventory.reports.vendor_basket.stats.price_effect"))
      expect(response.body).to include(I18n.t("inventory.reports.vendor_basket.stats.mix_effect"))
      expect(response.body).to include(I18n.t("inventory.reports.vendor_basket.table_heading"))
      expect(response.body).to include(I18n.t("inventory.reports.vendor_basket.verify_badge"))
    end

    it "says so when nothing was purchased" do
      get admin_inventory_reports_vendor_basket_path(start_date: now_start, end_date: now_end)

      expect(response.body).to include(I18n.t("inventory.reports.vendor_basket.empty"))
    end

    it "is reachable from the inventory reports nav" do
      get admin_inventory_reports_valuation_path

      expect(response.body).to include(admin_inventory_reports_vendor_basket_path)
      expect(response.body).to include(I18n.t("inventory.tools.vendor_basket"))
    end

    it "exports as CSV" do
      tomatoes = ingredient("Tomatoes")
      invoice(on: now_start + 1, lines: { tomatoes => [10, 10_000] })

      get admin_inventory_reports_vendor_basket_path(format: :csv, start_date: now_start, end_date: now_end)

      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Tomatoes")
      expect(response.body).to include("Price effect")
    end
  end
end
