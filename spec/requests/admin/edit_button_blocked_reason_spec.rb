# frozen_string_literal: true

require "rails_helper"

# The Edit button on vendor/customer invoices and credit notes is always on
# screen: a link when editing is allowed, otherwise a disabled button whose
# tooltip says why.
RSpec.describe "Edit button blocked reason", type: :request do
  include Devise::Test::IntegrationHelpers

  def disabled_edit_with(text)
    doc = Nokogiri::HTML(response.body)
    button = doc.at_css("button[aria-disabled='true'][data-tooltip-target='trigger']")
    expect(button&.text&.strip).to eq(I18n.t("actions.edit"))
    expect(button.parent.at_css("[role='tooltip']").text).to include(text)
  end

  describe "vendor invoices and credit notes" do
    let(:company) { Current.company }
    let(:owner) { create(:user, :owner, company: company) }
    let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
    let(:location) { create(:location, :central_kitchen, company: company) }
    let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
    let!(:ingredient) do
      Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
        reorder_threshold: 1, cost_per_unit_cents: 1_000, quantity_on_hand: 0, company: company)
    end
    let(:invoice) do
      inv = VendorInvoice.new(supplier: supplier, location: location, user: owner, company: company,
        invoice_date: Date.current, received_on: Date.current, draft: false,
        vendor_invoice_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, quantity: 10, line_total_cents: 10_000 }
        })
      Inventory::ReceiveVendorInvoiceService.new(inv, owner).call
    end
    let(:credit_note) do
      VendorCreditNote.create!(
        supplier: supplier, user: owner, company: company, credit_note_date: Date.current,
        kind: "goods_return", location: location, vendor_invoice: invoice,
        vendor_credit_note_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, quantity: 1, line_total_pounds: "10.00", position: "0" }
        }
      )
    end

    before { sign_in owner }

    it "links to edit while the invoice is editable" do
      get admin_inventory_vendor_invoice_path(invoice)
      expect(response.body).to include(edit_admin_inventory_vendor_invoice_path(invoice))
    end

    it "disables edit and names the credit notes once one is applied" do
      post confirm_admin_inventory_vendor_credit_note_path(credit_note)

      get admin_inventory_vendor_invoice_path(invoice)
      expect(response.body).not_to include(edit_admin_inventory_vendor_invoice_path(invoice))
      disabled_edit_with(credit_note.reload.credit_note_number)
    end

    it "explains a missing permission to a user who can only view inventory" do
      sign_in create(:user, company: company, role: "sub_manager")

      get admin_inventory_vendor_invoice_path(invoice)
      expect(response.body).not_to include(edit_admin_inventory_vendor_invoice_path(invoice))
      disabled_edit_with(I18n.t("edit_blocked.no_permission"))
    end

    it "always shows a disabled edit on a vendor credit note" do
      get admin_inventory_vendor_credit_note_path(credit_note)
      disabled_edit_with(I18n.t("edit_blocked.vendor_credit_note.draft"))
    end

    it "reports each blocked state on the model" do
      expect(invoice.edit_blocked_reason).to be_nil
      invoice.update_columns(historical_settled_cents: 1)
      expect(invoice.edit_blocked_reason).to eq(:historical_settled)
      invoice.update_columns(credit_applied_cents: 1)
      expect(invoice.edit_blocked_reason).to eq(:credit_applied)
      invoice.update_columns(payment_status: "void")
      expect(invoice.edit_blocked_reason).to eq(:void)
      expect(invoice).not_to be_editable
    end
  end

  describe "customer invoices and credit notes" do
    let(:company) { create(:company, business_type: "distribution") }
    let(:owner) { create(:user, :owner, company: company) }
    let(:location) { create(:location, company: company) }
    let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }
    let(:invoice) do
      CustomerInvoice.create!(customer: customer, location: location, user: owner, company: company,
        invoice_date: Date.current, status: "draft")
    end

    before do
      Current.company = company
      sign_in owner
    end

    it "links to edit on a draft and disables it once confirmed" do
      get admin_sales_customer_invoice_path(invoice)
      expect(response.body).to include(edit_admin_sales_customer_invoice_path(invoice))

      invoice.update_columns(status: "confirmed")
      get admin_sales_customer_invoice_path(invoice)
      expect(response.body).not_to include(edit_admin_sales_customer_invoice_path(invoice))
      disabled_edit_with(I18n.t("edit_blocked.customer_invoice.confirmed"))
    end

    it "always shows a disabled edit on a customer credit note" do
      credit_note = CreditNote.create!(customer: customer, location: location, user: owner, company: company,
        credit_note_date: Date.current, status: "draft")

      get admin_sales_credit_note_path(credit_note)
      disabled_edit_with(I18n.t("edit_blocked.customer_credit_note.draft"))
    end
  end
end
