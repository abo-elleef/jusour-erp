# frozen_string_literal: true

require "rails_helper"

# Bazzar slice C: optional waybill photo + tracking number on a delivery
# invoice, at dispatch or any time after. No money/stock/status effect.
RSpec.describe "Admin::Sales shipping proof", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "regular") }
  let(:shipping_company) { create(:shipping_company, company: company) }
  let(:waybill) { fixture_file_upload("storefront_product.png", "image/png") }

  before do
    Current.company = company
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 100,
      quantity_remaining: 100, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  def custom_user(*permissions)
    role = Role.create!(company: company, name: "Sales #{permissions.size}", key: "sales_#{SecureRandom.hex(3)}",
      permissions: permissions + ["sales:see_all"]) # every role in the sales area holds it after the slice E migration
    create(:user, company: company, role: "custom", role_id: role.id)
  end

  def confirmed_invoice(fulfillment: "delivery")
    attrs = { company: company, customer: customer, user: owner, location: location, invoice_date: Date.current }
    attrs.merge!(if fulfillment == "delivery"
                   { payment_method: "cash_on_delivery", fulfillment_method: "delivery", shipping_company: shipping_company }
                 else
                   { payment_method: "cash", fulfillment_method: "pickup" }
                 end)
    inv = CustomerInvoice.new(attrs)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, owner).call
    inv.reload
  end

  def shipped_invoice
    inv = confirmed_invoice
    Sales::DispatchCustomerInvoiceService.new(inv, owner).call
    inv.reload
  end

  describe "at dispatch" do
    before { sign_in owner }

    it "shows the optional fields on the dispatch form" do
      inv = confirmed_invoice
      get admin_sales_customer_invoice_path(inv)
      expect(response.body).to include("customer_invoice[shipping_tracking_number]")
      expect(response.body).to include("customer_invoice[waybill_image]")
    end

    it "dispatches without them" do
      inv = confirmed_invoice
      post mark_dispatched_admin_sales_customer_invoice_path(inv)

      inv.reload
      expect(inv.shipping_status).to eq("shipped")
      expect(inv.shipping_tracking_number).to be_nil
      expect(inv.waybill_image).not_to be_attached
    end

    it "saves the tracking number and waybill with the dispatch" do
      inv = confirmed_invoice
      post mark_dispatched_admin_sales_customer_invoice_path(inv),
        params: { customer_invoice: { shipping_tracking_number: "  BOS-12345 ", waybill_image: waybill } }

      inv.reload
      expect(inv.shipping_status).to eq("shipped")
      expect(inv.shipping_tracking_number).to eq("BOS-12345")
      expect(inv.waybill_image).to be_attached
    end

    it "refuses the whole dispatch when the waybill is not an image" do
      inv = confirmed_invoice
      post mark_dispatched_admin_sales_customer_invoice_path(inv),
        params: { customer_invoice: { shipping_tracking_number: "X1",
                                      waybill_image: fixture_file_upload("not_an_image.txt", "text/plain") } }

      inv.reload
      expect(inv.shipping_status).to eq("waiting_for_shipping")
      expect(inv.shipping_tracking_number).to be_nil
      expect(shipping_company.reload.balance_cents).to eq(0)
      expect(flash[:alert]).to be_present
    end
  end

  describe "adding them later" do
    it "adds and changes both on a shipped invoice, without touching its status or money" do
      sign_in owner
      inv = shipped_invoice
      balance = shipping_company.reload.balance_cents

      patch update_shipping_proof_admin_sales_customer_invoice_path(inv),
        params: { customer_invoice: { shipping_tracking_number: "TRK-1", waybill_image: waybill } }
      expect(response).to redirect_to(admin_sales_customer_invoice_path(inv))
      inv.reload
      expect(inv.shipping_tracking_number).to eq("TRK-1")
      expect(inv.waybill_image).to be_attached

      # A blank photo keeps the current one; the tracking number changes.
      patch update_shipping_proof_admin_sales_customer_invoice_path(inv),
        params: { customer_invoice: { shipping_tracking_number: "TRK-2", waybill_image: "" } }
      inv.reload
      expect(inv.shipping_tracking_number).to eq("TRK-2")
      expect(inv.waybill_image).to be_attached
      expect(inv.shipping_status).to eq("shipped")
      expect(shipping_company.reload.balance_cents).to eq(balance)

      get admin_sales_customer_invoice_path(inv)
      expect(response.body).to include("TRK-2")
      expect(response.body).to include('data-controller="clipboard"')
    end

    it "works on a shipping-completed invoice for a sales:complete_shipping holder" do
      inv = shipped_invoice
      Sales::CompleteShippingService.new(inv, owner).call
      sign_in custom_user("customers:manage", "sales:complete_shipping")

      patch update_shipping_proof_admin_sales_customer_invoice_path(inv),
        params: { customer_invoice: { shipping_tracking_number: "DONE-9" } }

      expect(inv.reload.shipping_tracking_number).to eq("DONE-9")
      expect(inv.shipping_status).to eq("shipping_completed")
    end

    it "works for a sales:dispatch holder" do
      inv = shipped_invoice
      sign_in custom_user("customers:manage", "sales:dispatch")

      patch update_shipping_proof_admin_sales_customer_invoice_path(inv),
        params: { customer_invoice: { shipping_tracking_number: "D-1" } }

      expect(inv.reload.shipping_tracking_number).to eq("D-1")
    end

    it "is refused for a pickup invoice" do
      sign_in owner
      inv = confirmed_invoice(fulfillment: "pickup")
      expect(inv.shipping_status).to be_nil

      patch update_shipping_proof_admin_sales_customer_invoice_path(inv),
        params: { customer_invoice: { shipping_tracking_number: "NOPE" } }

      expect(inv.reload.shipping_tracking_number).to be_nil
      expect(flash[:alert]).to eq(I18n.t("sales.customer_invoices.flash.cannot_update_shipping_proof", locale: :ar))
      get admin_sales_customer_invoice_path(inv)
      expect(response.body).not_to include(update_shipping_proof_admin_sales_customer_invoice_path(inv))
    end

    it "is refused before dispatch (use the dispatch form)" do
      sign_in owner
      inv = confirmed_invoice
      patch update_shipping_proof_admin_sales_customer_invoice_path(inv),
        params: { customer_invoice: { shipping_tracking_number: "EARLY" } }
      expect(inv.reload.shipping_tracking_number).to be_nil
    end

    it "is refused without sales:dispatch or sales:complete_shipping" do
      inv = shipped_invoice
      sign_in custom_user("customers:manage", "sales:view")

      patch update_shipping_proof_admin_sales_customer_invoice_path(inv),
        params: { customer_invoice: { shipping_tracking_number: "HACK" } }

      expect(inv.reload.shipping_tracking_number).to be_nil
    end
  end

  describe "the list" do
    it "shows the tracking number and finds an invoice by it" do
      sign_in owner
      found = shipped_invoice
      found.update!(shipping_tracking_number: "ABC-777")
      other = shipped_invoice

      get admin_sales_customer_invoices_path
      expect(response.body).to include("ABC-777")

      get admin_sales_customer_invoices_path(tracking: "abc-7")
      expect(response.body).to include(found.invoice_number)
      expect(response.body).not_to include(other.invoice_number)
    end
  end
end
