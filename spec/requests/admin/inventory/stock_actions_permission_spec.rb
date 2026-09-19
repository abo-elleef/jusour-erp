# frozen_string_literal: true

require "rails_helper"

# Moving stock that already exists — adjusting it, consolidating it, voiding the
# invoice that brought it in — is inventory:manage. The controllers have always
# said so; these specs pin the *buttons* to the same answer, so nobody is shown
# a control whose only outcome is an "unauthorized" flash.
RSpec.describe "Who can move stock", type: :request do
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
      reorder_threshold: 10, cost_per_unit_cents: 250, quantity_on_hand: 0, company: company)
  end

  # Posted through the controller so the invoice is a real, landed one.
  let!(:invoice) do
    sign_in owner
    post admin_inventory_vendor_invoices_path, params: { vendor_invoice: {
      supplier_id: supplier.id, location_id: location.id,
      invoice_date: Date.current, received_on: Date.current,
      vendor_invoice_lines_attributes: {
        "0" => { ingredient_id: ingredient.id, quantity: 4, line_total_dollars: "10.00" }
      }
    } }
    sign_out owner
    VendorInvoice.order(:created_at).last
  end

  def adjust!
    post adjust_admin_inventory_ingredient_path(ingredient), params: {
      location_id: location.id, quantity_delta: "5", unit: "kg",
      adjustment_type: StockAdjustment::ADJUSTMENT_TYPES.first, reason_notes: "recount"
    }
  end

  context "a sub-manager (inventory:view, no inventory:manage)" do
    let(:sub_manager) { create(:user, company: company, role: "sub_manager") }

    before { sign_in sub_manager }

    it "reads the screens but is offered none of the three controls" do
      get admin_inventory_ingredient_path(ingredient)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("adjust-stock-modal")
      expect(response.body).not_to include(new_admin_inventory_ingredient_consolidation_path(ingredient))

      get admin_inventory_ingredients_path
      expect(response.body).not_to include(admin_inventory_ingredient_path(ingredient, anchor: "adjust"))

      get low_stock_admin_inventory_ingredients_path
      expect(response.body).not_to include(admin_inventory_ingredient_path(ingredient, anchor: "adjust"))

      get admin_inventory_vendor_invoice_path(invoice)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(void_admin_inventory_vendor_invoice_path(invoice))
    end

    it "cannot adjust stock" do
      expect { adjust! }.not_to change(StockAdjustment, :count)
    end

    it "cannot consolidate stock" do
      get new_admin_inventory_ingredient_consolidation_path(ingredient)
      expect(response).to have_http_status(:redirect)

      post admin_inventory_ingredient_consolidation_path(ingredient), params: { target_id: ingredient.id }
      expect(response).to have_http_status(:redirect)
    end

    it "cannot void the invoice" do
      patch void_admin_inventory_vendor_invoice_path(invoice)
      expect(invoice.reload).not_to be_void
    end
  end

  context "a manager (holds inventory:manage)" do
    let(:manager) { create(:user, :manager, company: company) }

    before { sign_in manager }

    it "is offered all three controls" do
      get admin_inventory_ingredient_path(ingredient)
      expect(response.body).to include("adjust-stock-modal")
      expect(response.body).to include(new_admin_inventory_ingredient_consolidation_path(ingredient))

      get admin_inventory_vendor_invoice_path(invoice)
      expect(response.body).to include(void_admin_inventory_vendor_invoice_path(invoice))
    end

    it "adjusts stock" do
      expect { adjust! }.to change(StockAdjustment, :count).by(1)
    end

    it "voids the invoice" do
      patch void_admin_inventory_vendor_invoice_path(invoice)
      expect(invoice.reload).to be_void
    end
  end
end
