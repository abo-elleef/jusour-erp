# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Vendor invoice drafts", type: :request do
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
      reorder_threshold: 1, cost_per_unit_cents: 250, quantity_on_hand: 0, company: company)
  end
  let!(:other) do
    Ingredient.create!(name: "Onions", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 100, quantity_on_hand: 0, company: company)
  end

  before { sign_in owner }

  def base_params(lines, extra = {})
    { vendor_invoice: {
        supplier_id: supplier.id, location_id: location.id,
        invoice_date: Date.current, received_on: Date.current,
        vendor_invoice_lines_attributes: lines
      }.merge(extra) }
  end

  def one_line(qty: 4, total: "10.00", ing: nil)
    { "0" => { ingredient_id: (ing || ingredient).id, quantity: qty, line_total_dollars: total } }
  end

  describe "saving a draft" do
    it "posts nothing — no stock, no AP, no journal, no cash" do
      expect {
        post admin_inventory_vendor_invoices_path, params: base_params(one_line).merge(save_draft: "1")
      }.to change(VendorInvoice, :count).by(1)
        .and change(StockBatch, :count).by(0)
        .and change(StockAdjustment, :count).by(0)
        .and change(TreasuryTransaction, :count).by(0)
        .and change(JournalEntry, :count).by(0)
        .and change(SupplierPriceHistory, :count).by(0)

      expect(treasury.reload.balance_cents).to eq(500_000)
      expect(VendorInvoice.order(:created_at).last).to be_draft
    end

    it "keeps a line whose quantity is not filled in yet" do
      post admin_inventory_vendor_invoices_path,
        params: base_params({
          "0" => { ingredient_id: ingredient.id, quantity: 4, line_total_dollars: "10.00" },
          "1" => { ingredient_id: other.id, quantity: "", line_total_dollars: "" }
        }).merge(save_draft: "1")

      invoice = VendorInvoice.order(:created_at).last
      expect(invoice.vendor_invoice_lines.count).to eq(2)
    end

    it "saves with no lines at all" do
      post admin_inventory_vendor_invoices_path,
        params: base_params({}).merge(save_draft: "1")

      expect(VendorInvoice.order(:created_at).last).to be_draft
    end

    it "does not add to the supplier balance" do
      post admin_inventory_vendor_invoices_path, params: base_params(one_line).merge(save_draft: "1")

      expect(supplier.reload.ap_treasury&.balance_cents.to_i).to eq(0)
    end
  end

  describe "editing a draft" do
    let(:draft) do
      post admin_inventory_vendor_invoices_path, params: base_params(one_line).merge(save_draft: "1")
      VendorInvoice.order(:created_at).last
    end

    it "is always editable — there is nothing to unwind" do
      expect(draft).to be_editable
    end

    it "saves again without receiving anything" do
      line = draft.vendor_invoice_lines.first

      expect {
        patch admin_inventory_vendor_invoice_path(draft), params: base_params({
          "0" => { id: line.id, ingredient_id: ingredient.id, quantity: 9, line_total_dollars: "20.00" }
        }).merge(save_draft: "1")
      }.not_to change(StockBatch, :count)

      expect(draft.reload).to be_draft
      expect(line.reload.quantity).to eq(9)
    end
  end

  describe "receiving a draft" do
    let(:draft) do
      post admin_inventory_vendor_invoices_path, params: base_params(one_line).merge(save_draft: "1")
      VendorInvoice.order(:created_at).last
    end

    it "adds the stock and posts the supplier balance" do
      expect { post receive_admin_inventory_vendor_invoice_path(draft) }
        .to change(StockBatch, :count).by(1)

      draft.reload
      expect(draft).not_to be_draft
      expect(supplier.reload.ap_treasury.balance_cents).to eq(1_000)
    end

    it "records the price history only once received" do
      expect { post receive_admin_inventory_vendor_invoice_path(draft) }
        .to change(SupplierPriceHistory, :count).by(1)
    end

    it "refuses a draft with an unpriced line, naming it" do
      post admin_inventory_vendor_invoices_path,
        params: base_params({
          "0" => { ingredient_id: ingredient.id, quantity: 4, line_total_dollars: "10.00" },
          "1" => { ingredient_id: other.id, quantity: "", line_total_dollars: "" }
        }).merge(save_draft: "1")
      incomplete = VendorInvoice.order(:created_at).last

      expect { post receive_admin_inventory_vendor_invoice_path(incomplete) }
        .not_to change(StockBatch, :count)
      expect(incomplete.reload).to be_draft
      expect(flash[:alert]).to include(other.name)
    end

    it "refuses an empty draft" do
      post admin_inventory_vendor_invoices_path, params: base_params({}).merge(save_draft: "1")
      empty = VendorInvoice.order(:created_at).last

      post receive_admin_inventory_vendor_invoice_path(empty)

      expect(empty.reload).to be_draft
      expect(flash[:alert]).to be_present
    end

    it "refuses to receive something already received" do
      post receive_admin_inventory_vendor_invoice_path(draft)

      post receive_admin_inventory_vendor_invoice_path(draft.reload)

      expect(flash[:alert]).to eq(I18n.t("inventory.vendor_invoices.errors.not_a_draft"))
    end
  end

  describe "drafts stay out of real activity" do
    before do
      post admin_inventory_vendor_invoices_path,
        params: base_params(one_line(total: "99.00")).merge(save_draft: "1")
    end

    it "is not offered as the last invoiced cost" do
      # Nothing was received at that price, so it must not become the master cost.
      expect(::Inventory::IngredientLastInvoiceCost.new(ingredient.reload).call).to be_nil
    end

    it "is absent from the supplier's purchase history" do
      get admin_inventory_supplier_path(supplier)

      expect(response.body).not_to include(VendorInvoice.order(:created_at).last.invoice_number)
    end
  end

  describe "the UI" do
    it "offers the draft button on a new invoice" do
      get new_admin_inventory_vendor_invoice_path

      expect(response.body).to include(I18n.t("inventory.vendor_invoices.save_draft"))
      expect(response.body).to include('name="save_draft"')
    end

    it "marks a draft and offers to receive it" do
      post admin_inventory_vendor_invoices_path, params: base_params(one_line).merge(save_draft: "1")
      draft = VendorInvoice.order(:created_at).last

      get admin_inventory_vendor_invoice_path(draft)

      expect(response.body).to include(I18n.t("inventory.vendor_invoices.draft_badge"))
      expect(response.body).to include(I18n.t("inventory.vendor_invoices.receive_invoice"))
    end
  end
end
