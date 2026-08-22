# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Supplier price history", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
  let(:location) { create(:location, :central_kitchen, company: company) }
  let!(:treasury) do
    Treasury.create!(name: "Main Safe", treasury_type: "safe",
      balance_cents: 500_000, opening_balance_cents: 500_000,
      is_default: true, company: company)
  end
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }

  def ingredient(name)
    Ingredient.create!(name: name, ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 250, quantity_on_hand: 0, company: company)
  end

  let!(:tomatoes) { ingredient("Tomatoes") }

  before { sign_in owner }

  def showing(from, to, count)
    I18n.t("accounting.shared.pagination_showing", from: from, to: to, count: count)
  end

  def post_invoice(ing: tomatoes, quantity: 4, total: "10.00", invoice_date: Date.current)
    post admin_inventory_vendor_invoices_path, params: {
      vendor_invoice: {
        supplier_id: supplier.id, location_id: location.id,
        invoice_date: invoice_date, received_on: invoice_date,
        vendor_invoice_lines_attributes: {
          "0" => { ingredient_id: ing.id, quantity: quantity, line_total_dollars: total }
        }
      }
    }
    VendorInvoice.order(:created_at).last
  end

  describe "recording" do
    it "stamps the originating invoice line and the receiving user" do
      invoice = post_invoice

      row = SupplierPriceHistory.order(:created_at).last
      expect(row.vendor_invoice_line).to eq(invoice.vendor_invoice_lines.first)
      expect(row.recorded_by_user).to eq(owner)
      # 10.00 over 4 kg → 250 cents per base unit.
      expect(row.price_cents).to eq(250)
    end

    it "keeps one row when the price does not move" do
      post_invoice(total: "10.00")
      expect { post_invoice(total: "10.00") }.not_to change(SupplierPriceHistory, :count)
    end

    it "adds a row when the price moves" do
      post_invoice(total: "10.00")
      expect { post_invoice(total: "20.00") }.to change(SupplierPriceHistory, :count).by(1)
    end
  end

  describe "same-day receipts (notice 3)" do
    # Two deliveries can share an effective_date. The price that stands is the one
    # recorded last, so dedup must not read an arbitrary row as "the last price".
    it "treats the most recently recorded row as current" do
      post_invoice(total: "10.00")            # 250/kg
      post_invoice(total: "20.00")            # 500/kg, same date
      expect(SupplierPriceHistory.count).to eq(2)

      # Back to 250 is a genuine third change, not a duplicate of the first row.
      expect { post_invoice(total: "10.00") }.to change(SupplierPriceHistory, :count).by(1)

      expect(SupplierPriceHistory.most_recent_first.first.price_cents).to eq(250)
    end

    it "does not re-record a repeat of the latest same-day price" do
      post_invoice(total: "10.00")
      post_invoice(total: "20.00")

      expect { post_invoice(total: "20.00") }.not_to change(SupplierPriceHistory, :count)
    end
  end

  describe "correcting an invoice (notice 4)" do
    it "replaces the row instead of leaving the wrong price behind" do
      invoice = post_invoice(total: "10.00")
      expect(SupplierPriceHistory.pluck(:price_cents)).to eq([250])

      patch admin_inventory_vendor_invoice_path(invoice), params: {
        vendor_invoice: {
          supplier_id: supplier.id, location_id: location.id,
          invoice_date: invoice.invoice_date, received_on: invoice.received_on,
          vendor_invoice_lines_attributes: {
            "0" => { id: invoice.vendor_invoice_lines.first.id, ingredient_id: tomatoes.id,
                     quantity: 4, line_total_dollars: "12.00" }
          }
        }
      }

      # One row at the corrected price — not a 250 → 300 "increase" that never happened.
      expect(SupplierPriceHistory.pluck(:price_cents)).to eq([300])
    end

    it "leaves history alone when the invoice is voided, because the stock stays" do
      invoice = post_invoice(total: "10.00")

      # void is a PATCH; with the wrong verb this 404s and the test passes vacuously.
      expect { patch void_admin_inventory_vendor_invoice_path(invoice) }
        .not_to change(SupplierPriceHistory, :count)
      expect(invoice.reload.payment_status).to eq("void")
    end
  end

  describe "the supplier page" do
    # Without the frame, filtering is a full navigation that resets the admin
    # shell's scroll container and dumps the user at the top of a long page.
    it "renders the section in a Turbo frame so filtering keeps the scroll position" do
      post_invoice

      get admin_inventory_supplier_path(supplier)

      expect(response.body).to include('id="supplier_price_history"')
      expect(response.body).to include("turbo-frame")
    end

    it "does not disable Turbo on the filter form — the frame needs it" do
      post_invoice

      get admin_inventory_supplier_path(supplier)

      form = response.body[/<form[^>]*ph_ingredient_id.*?<\/form>/m] ||
             response.body[/<form(?:(?!<\/form>).)*?searchable-select.*?<\/form>/m]
      expect(response.body).to include("supplier_price_history")
      expect(form.to_s).not_to include('data-turbo="false"')
    end

    it "shows who received the price and links the invoice (notice 2)" do
      invoice = post_invoice

      get admin_inventory_supplier_path(supplier)

      expect(response.body).to include(I18n.t("inventory.suppliers.show.price_history_recorded_by"))
      expect(response.body).to include(owner.name)
      expect(response.body).to include(invoice.invoice_number)
    end

    it "filters by ingredient (notice 1)" do
      onions = ingredient("Onions")
      post_invoice(ing: tomatoes)
      post_invoice(ing: onions, total: "30.00")

      # Row count is the precise signal: the ingredient name also appears in the
      # supplier's ingredient table and in the filter's own option list.
      get admin_inventory_supplier_path(supplier)
      expect(response.body).to include(showing(1, 2, 2))

      get admin_inventory_supplier_path(supplier, ph_ingredient_id: onions.id)
      expect(response.body).to include(showing(1, 1, 1))
      expect(response.body).to include("Onions")
    end

    it "says so when the filtered ingredient has no changes" do
      spinach = ingredient("Spinach")
      post_invoice(ing: tomatoes)

      get admin_inventory_supplier_path(supplier, ph_ingredient_id: spinach.id)

      expect(response.body).to include(I18n.t("inventory.suppliers.show.price_history_filtered_empty"))
    end

    it "paginates instead of silently truncating" do
      # 26 distinct ingredients → 26 rows, one page of 25 plus a second page.
      26.times { |i| post_invoice(ing: ingredient("Herb #{i}"), total: "#{i + 1}.00") }

      get admin_inventory_supplier_path(supplier)

      expect(response.body).to include(showing(1, 25, 26))
    end
  end
end
