# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Filling ingredient cost from the last invoice", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
  let(:location) { create(:location, :central_kitchen, company: company) }
  let!(:treasury) do
    Treasury.create!(name: "Main Safe", treasury_type: "safe", balance_cents: 500_000,
      opening_balance_cents: 500_000, is_default: true, company: company)
  end
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:ingredient) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 10_000, quantity_on_hand: 0, company: company)
  end

  before { sign_in owner }

  def receive_invoice(total:, quantity: 4, on: Date.current)
    post admin_inventory_vendor_invoices_path, params: {
      vendor_invoice: {
        supplier_id: supplier.id, location_id: location.id,
        invoice_date: on, received_on: on,
        vendor_invoice_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, quantity: quantity, line_total_dollars: total }
        }
      }
    }
    VendorInvoice.order(:created_at).last
  end

  describe "the offer on the ingredient page" do
    it "is absent when the ingredient was never invoiced" do
      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).not_to include(I18n.t("inventory.ingredients.cost_sync.action"))
    end

    it "offers the last invoiced price and names the source invoice" do
      invoice = receive_invoice(total: "10.00") # 1000c / 4kg = 250c per kg

      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).to include(I18n.t("inventory.ingredients.cost_sync.action"))
      # The guard spells out the before/after, the invoice and how many invoices.
      expect(response.body).to include(invoice.invoice_number)
      expect(response.body).to include("data-turbo-confirm")
    end

    it "says it is in sync instead of offering a no-op change" do
      invoice = receive_invoice(total: "10.00")
      ingredient.update!(cost_per_unit_cents: 250)

      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).not_to include(I18n.t("inventory.ingredients.cost_sync.action"))
      expect(response.body).to include(invoice.invoice_number)
      expect(response.body).to include(admin_inventory_vendor_invoice_path(invoice))
    end

    it "links the invoice number so it can be opened directly" do
      invoice = receive_invoice(total: "10.00")

      get admin_inventory_ingredient_path(ingredient)

      # The number is rendered as an anchor to the invoice, in both card states.
      expect(response.body).to match(
        /<a[^>]*href="#{Regexp.escape(admin_inventory_vendor_invoice_path(invoice))}"[^>]*>\s*#{Regexp.escape(invoice.invoice_number)}\s*<\/a>/
      )
    end

    it "links the invoice in the in-sync state too" do
      invoice = receive_invoice(total: "10.00")
      ingredient.update!(cost_per_unit_cents: 250)

      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).to match(
        /<a[^>]*href="#{Regexp.escape(admin_inventory_vendor_invoice_path(invoice))}"[^>]*>\s*#{Regexp.escape(invoice.invoice_number)}\s*<\/a>/
      )
    end

    it "does not emit escaped markup from the _html translation" do
      receive_invoice(total: "10.00")

      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).not_to include("&lt;a href")
    end
  end

  describe "applying it" do
    it "adopts the last invoiced unit cost" do
      invoice = receive_invoice(total: "10.00")

      post sync_cost_from_last_invoice_admin_inventory_ingredient_path(ingredient)

      expect(ingredient.reload.cost_per_unit_cents).to eq(250)
      expect(flash[:notice]).to include(invoice.invoice_number)
    end

    it "uses the most recent invoice, not the first" do
      receive_invoice(total: "10.00", on: Date.current - 5)  # 250
      receive_invoice(total: "40.00", on: Date.current)      # 1000

      post sync_cost_from_last_invoice_admin_inventory_ingredient_path(ingredient)

      expect(ingredient.reload.cost_per_unit_cents).to eq(1_000)
    end

    it "refuses when there is nothing to copy from" do
      post sync_cost_from_last_invoice_admin_inventory_ingredient_path(ingredient)

      expect(ingredient.reload.cost_per_unit_cents).to eq(10_000)
      expect(flash[:alert]).to eq(I18n.t("inventory.ingredients.cost_sync.unavailable"))
    end

    it "never fills the cost with zero" do
      # A zero-value line would wipe the cost — it must be skipped, not adopted.
      receive_invoice(total: "10.00", on: Date.current - 3)
      receive_invoice(total: "0", on: Date.current)

      post sync_cost_from_last_invoice_admin_inventory_ingredient_path(ingredient)

      expect(ingredient.reload.cost_per_unit_cents).to eq(250)
    end

    it "ignores a voided invoice" do
      receive_invoice(total: "10.00", on: Date.current - 3)
      voided = receive_invoice(total: "99.00", on: Date.current)

      patch void_admin_inventory_vendor_invoice_path(voided)
      # Guard the guard: if the void silently failed this test would pass vacuously.
      expect(voided.reload.payment_status).to eq("void")

      post sync_cost_from_last_invoice_admin_inventory_ingredient_path(ingredient)

      expect(ingredient.reload.cost_per_unit_cents).to eq(250)
    end
  end
end
