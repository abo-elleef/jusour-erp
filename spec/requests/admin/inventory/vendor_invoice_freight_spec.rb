# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Vendor invoice courier freight", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
  let(:location) { create(:location, :central_kitchen, company: company) }
  let!(:treasury) do
    Treasury.create!(
      name: "Main Safe", treasury_type: "safe",
      balance_cents: 500_000, opening_balance_cents: 500_000,
      is_default: true, company: company
    )
  end
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:ingredient) do
    Ingredient.create!(
      name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 250, quantity_on_hand: 0, company: company
    )
  end

  before { sign_in owner }

  def invoice_params(freight_dollars: nil, freight_treasury_id: nil)
    {
      vendor_invoice: {
        supplier_id: supplier.id,
        location_id: location.id,
        invoice_date: Date.current,
        received_on: Date.current,
        freight_amount_dollars: freight_dollars,
        freight_treasury_id: freight_treasury_id,
        vendor_invoice_lines_attributes: {
          "0" => {
            ingredient_id: ingredient.id,
            quantity: 4,
            line_total_dollars: "10.00"
          }
        }
      }
    }
  end

  it "receives freight as a linked expense without changing supplier AP total" do
    expect {
      post admin_inventory_vendor_invoices_path, params: invoice_params(
        freight_dollars: "50.00",
        freight_treasury_id: treasury.id
      )
    }.to change(VendorInvoice, :count).by(1)
      .and change(Expense, :count).by(1)

    invoice = VendorInvoice.order(:created_at).last
    expect(response).to redirect_to(admin_inventory_vendor_invoice_path(invoice))
    expect(invoice.total_cents).to eq(1_000)

    ap_txn = TreasuryTransaction.find_by!(source_record: invoice, kind: "ap_invoice")
    expect(ap_txn.amount_cents).to eq(1_000)

    freight = invoice.freight_expense
    expect(freight).to have_attributes(
      amount_cents: 5_000,
      expense_category: ExpenseCategory.find_by!(name: "Goods delivery", company: company)
    )

    get admin_inventory_vendor_invoice_path(invoice)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("inventory.vendor_invoices.freight"))
    expect(response.body).to include(I18n.t("inventory.vendor_invoices.view_freight_expense"))
  end

  it "rejects positive freight without a treasury" do
    expect {
      post admin_inventory_vendor_invoices_path, params: invoice_params(freight_dollars: "20.00")
    }.not_to change(VendorInvoice, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t("inventory.vendor_invoices.errors.freight_treasury_required"))
  end

  it "clears freight on edit when amount is blanked and voids with the invoice" do
    post admin_inventory_vendor_invoices_path, params: invoice_params(
      freight_dollars: "30.00",
      freight_treasury_id: treasury.id
    )
    invoice = VendorInvoice.order(:created_at).last
    freight_id = invoice.freight_expense.id

    patch admin_inventory_vendor_invoice_path(invoice), params: {
      vendor_invoice: {
        supplier_id: supplier.id,
        location_id: location.id,
        invoice_date: invoice.invoice_date,
        received_on: invoice.received_on,
        freight_amount_dollars: "",
        freight_treasury_id: treasury.id,
        vendor_invoice_lines_attributes: {
          "0" => {
            id: invoice.vendor_invoice_lines.first.id,
            ingredient_id: ingredient.id,
            quantity: 4,
            line_total_dollars: "10.00"
          }
        }
      }
    }
    expect(invoice.reload.freight_expense).to be_nil
    expect(Expense.find_by(id: freight_id)).to be_nil

    post admin_inventory_vendor_invoices_path, params: invoice_params(
      freight_dollars: "25.00",
      freight_treasury_id: treasury.id
    )
    invoice2 = VendorInvoice.order(:created_at).last
    freight2_id = invoice2.freight_expense.id

    patch void_admin_inventory_vendor_invoice_path(invoice2)
    expect(Expense.find_by(id: freight2_id)).to be_nil
    expect(invoice2.reload).to be_void
  end
end
