# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales::CustomerInvoices", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }

  before do
    Current.company = company
    sign_in owner
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 100,
      quantity_remaining: 100, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  def line_attrs
    { "0" => { ingredient_id: ingredient.id, quantity: "5", unit: ingredient.unit, unit_price_pounds: "20" } }
  end

  it "makes the quantity field refuse fractions unless the owner allows them" do
    get new_admin_sales_customer_invoice_path
    expect(response.body).to include('data-arabic-numerals-whole-value="true"')

    Current.company = company # the request above resets it
    Setting.set("allow_fractional_sales_quantities", true)
    get new_admin_sales_customer_invoice_path
    expect(response.body).to include('data-arabic-numerals-whole-value="false"')
    expect(response.body).to include('inputmode="decimal"')
  end

  it "lists and opens the new form" do
    get admin_sales_customer_invoices_path
    expect(response).to have_http_status(:ok)
    get new_admin_sales_customer_invoice_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("customer-invoice-lines")
  end

  describe "settling at the counter" do
    it "creates and confirms a cash sale in one go, with no receivable" do
      post admin_sales_customer_invoices_path, params: {
        commit_action: "confirm",
        customer_invoice: { customer_id: customer.id, location_id: location.id,
          invoice_date: Date.current, payment_method: "cash",
          customer_invoice_lines_attributes: line_attrs }
      }

      inv = CustomerInvoice.last
      expect(inv.payment_method).to eq("cash")
      expect(inv.status).to eq("confirmed")
      expect(inv.payment_status).to eq("paid")
      expect(inv.treasury).to eq(owner.assigned_treasury)
      expect(customer.reload.ar_balance_cents).to eq(0)
    end

    it "defaults to on account when nothing is chosen" do
      post admin_sales_customer_invoices_path, params: {
        commit_action: "draft",
        customer_invoice: { customer_id: customer.id, location_id: location.id,
          invoice_date: Date.current, customer_invoice_lines_attributes: line_attrs }
      }

      expect(CustomerInvoice.last.payment_method).to eq("on_account")
    end

    it "offers walk-in customers, not only commercial ones" do
      walk_in = create(:customer, company: company, name: "Dr Walk-in", customer_type: "regular")

      get new_admin_sales_customer_invoice_path(locale: "en")
      expect(response.body).to include(walk_in.name)
    end
  end

  describe "historical (imported) documents" do
    let!(:historical) do
      inv = CustomerInvoice.new(company: company, customer: customer, user: owner,
        location: location, invoice_date: Date.new(2026, 1, 3), legacy_number: "2052",
        notes: "Legacy invoice #2052")
      inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5,
        unit: ingredient.unit, unit_price_cents: 20_000)
      inv.save!
      inv.update_columns(status: "historical")
      inv
    end

    it "shows them on the index under their own filter" do
      get admin_sales_customer_invoices_path(status: "historical", locale: "en")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(historical.invoice_number)
      expect(response.body).to include("Historical")
    end

    it "excludes them from the draft filter and the outstanding total" do
      get admin_sales_customer_invoices_path(status: "draft", locale: "en")
      expect(response.body).not_to include(historical.invoice_number)
      expect(CustomerInvoice.outstanding.sum(:total_cents)).to eq(0)
    end

    it "filters the index to one customer" do
      other = create(:customer, company: company, name: "Other clinic", customer_type: "commercial")
      other_inv = CustomerInvoice.new(company: company, customer: other, user: owner,
        location: location, invoice_date: Date.current)
      other_inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1,
        unit: ingredient.unit, unit_price_cents: 1_000)
      other_inv.save!

      get admin_sales_customer_invoices_path(customer_id: customer.id, locale: "en")
      expect(response.body).to include(historical.invoice_number)
      expect(response.body).not_to include(other_inv.invoice_number)
    end

    it "filters the index by invoice date range and ignores a malformed date" do
      get admin_sales_customer_invoices_path(from_date: "2026-01-01", to_date: "2026-01-31", locale: "en")
      expect(response.body).to include(historical.invoice_number)

      get admin_sales_customer_invoices_path(from_date: "2026-01-04", locale: "en")
      expect(response.body).not_to include(historical.invoice_number)

      get admin_sales_customer_invoices_path(to_date: "not-a-date", locale: "en")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(historical.invoice_number)
    end

    it "lists them on the customer page, with a link to the invoice" do
      get admin_customer_path(customer, locale: "en")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sales invoices")
      expect(response.body).to include(admin_sales_customer_invoice_path(historical))
      expect(response.body).not_to include("Order history")
    end

    it "links the customer, location and seller from the invoice header" do
      get admin_sales_customer_invoice_path(historical, locale: "en")
      expect(response.body).to include(admin_customer_path(customer))
      expect(response.body).to include(admin_location_path(location))
      expect(response.body).to include(admin_user_path(owner))
    end

    it "explains itself on the show page instead of offering a payment form" do
      get admin_sales_customer_invoice_path(historical, locale: "en")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Imported from the previous system")
      expect(response.body).not_to include("Record a payment")
      expect(response.body).not_to include("Confirm sale")
    end

    it "refuses to confirm one" do
      post confirm_admin_sales_customer_invoice_path(historical)
      expect(historical.reload.status).to eq("historical")
      expect(customer.reload.ar_balance_cents).to eq(0)
    end
  end

  it "creates a draft" do
    expect {
      post admin_sales_customer_invoices_path, params: {
        commit_action: "draft",
        customer_invoice: { customer_id: customer.id, location_id: location.id,
          invoice_date: Date.current, customer_invoice_lines_attributes: line_attrs }
      }
    }.to change(CustomerInvoice, :count).by(1)

    inv = CustomerInvoice.last
    expect(inv.status).to eq("draft")
    expect(inv.total_cents).to eq(10_000) # 5 × 20.00
    expect(response).to redirect_to(admin_sales_customer_invoice_path(inv))
  end

  describe "typed unit price" do
    before { ingredient.update!(selling_price_cents: 2_000, cost_per_unit_cents: 1_500) }

    it "offers an editable price box that takes Arabic-Indic digits" do
      get new_admin_sales_customer_invoice_path
      expect(response.body).to match(/<input[^>]*data-role="price"[^>]*>/)
      price_input = response.body[/<input[^>]*data-role="price"[^>]*>/]
      expect(price_input).to include('type="text"', 'inputmode="decimal"', "arabic-numerals")
      expect(price_input).not_to include('type="hidden"')
    end

    it "saves a typed price, flags it as changed, and shows the badge" do
      post admin_sales_customer_invoices_path, params: {
        commit_action: "draft",
        customer_invoice: { customer_id: customer.id, location_id: location.id, invoice_date: Date.current,
          customer_invoice_lines_attributes: { "0" => { ingredient_id: ingredient.id, quantity: "2",
                                                         unit: ingredient.unit, unit_price_pounds: "17.5" } } }
      }

      inv = CustomerInvoice.last
      line = inv.customer_invoice_lines.first
      expect(line.unit_price_cents).to eq(1_750)
      expect(line.price_overridden).to be(true)
      expect(inv.total_cents).to eq(3_500)

      follow_redirect!
      expect(response.body).to include(I18n.t("sales.customer_invoices.show.price_changed"))
      expect(response.body).not_to include(I18n.t("sales.customer_invoices.show.below_cost"))
    end

    it "warns about a below-cost price but still saves and confirms" do
      post admin_sales_customer_invoices_path, params: {
        commit_action: "confirm",
        customer_invoice: { customer_id: customer.id, location_id: location.id, invoice_date: Date.current,
          customer_invoice_lines_attributes: { "0" => { ingredient_id: ingredient.id, quantity: "2",
                                                         unit: ingredient.unit, unit_price_pounds: "10" } } }
      }

      inv = CustomerInvoice.last
      expect(inv.status).to eq("confirmed")
      expect(inv.total_cents).to eq(2_000)

      get admin_sales_customer_invoice_path(inv)
      expect(response.body).to include(I18n.t("sales.customer_invoices.show.below_cost"))
    end

    it "shows the below-cost warning on the edit form for a saved draft" do
      inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location, invoice_date: Date.current)
      inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 1_000)
      inv.save!

      get edit_admin_sales_customer_invoice_path(inv)
      warning = response.body[/<p class="([^"]*)"[^>]*data-role="below-cost"/, 1]
      expect(warning).not_to include("hidden")
    end

    it "does not mark a line whose price was left at the selling price" do
      post admin_sales_customer_invoices_path, params: {
        commit_action: "draft",
        customer_invoice: { customer_id: customer.id, location_id: location.id, invoice_date: Date.current,
          customer_invoice_lines_attributes: { "0" => { ingredient_id: ingredient.id, quantity: "2",
                                                         unit: ingredient.unit, unit_price_pounds: "20.00" } } }
      }

      expect(CustomerInvoice.last.customer_invoice_lines.first.price_overridden).to be(false)
      follow_redirect!
      expect(response.body).not_to include(I18n.t("sales.customer_invoices.show.price_changed"))
    end
  end

  describe "payment proof image" do
    let(:treasury) do
      Treasury.create!(name: "Bank", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
    end
    let(:proof) { fixture_file_upload("storefront_product.png", "image/png") }

    def online_params(method, **extra)
      { customer_id: customer.id, location_id: location.id, invoice_date: Date.current,
        payment_method: "online", sales_payment_method_id: method.id,
        customer_invoice_lines_attributes: line_attrs }.merge(extra)
    end

    context "when the method requires it" do
      let(:method) { create(:sales_payment_method, company: company, treasury: treasury, name: "InstaPay", requires_proof_image: true) }

      it "saves the draft but refuses to confirm without the image, with an Arabic message" do
        post admin_sales_customer_invoices_path, params: { commit_action: "confirm", locale: "ar",
                                                           customer_invoice: online_params(method) }

        inv = CustomerInvoice.last
        expect(inv.status).to eq("draft")
        expect(flash[:alert]).to eq(I18n.t("sales.customer_invoices.errors.payment_proof_missing", method: "InstaPay", locale: :ar))

        get admin_sales_customer_invoice_path(inv)
        expect(response.body).to include(I18n.t("sales.customer_invoices.show.payment_proof_missing", method: "InstaPay"))

        post confirm_admin_sales_customer_invoice_path(inv)
        expect(inv.reload.status).to eq("draft")
      end

      it "confirms once the image is attached from the show page" do
        post admin_sales_customer_invoices_path, params: { commit_action: "draft", customer_invoice: online_params(method) }
        inv = CustomerInvoice.last

        patch attach_payment_proof_image_admin_sales_customer_invoice_path(inv),
          params: { customer_invoice: { payment_proof_image: proof } }
        post confirm_admin_sales_customer_invoice_path(inv)

        expect(inv.reload.status).to eq("pending_payment_confirmation")
      end

      it "accepts the image on the form itself" do
        post admin_sales_customer_invoices_path, params: { commit_action: "confirm",
                                                           customer_invoice: online_params(method, payment_proof_image: proof) }

        inv = CustomerInvoice.last
        expect(inv.payment_proof_image).to be_attached
        expect(inv.status).to eq("pending_payment_confirmation")
      end
    end

    it "confirms without an image when the method doesn't require one" do
      method = create(:sales_payment_method, company: company, treasury: treasury, name: "CIB")
      post admin_sales_customer_invoices_path, params: { commit_action: "confirm", customer_invoice: online_params(method) }

      expect(CustomerInvoice.last.status).to eq("pending_payment_confirmation")
    end
  end

  it "creates and confirms in one step (raises AR, deducts stock)" do
    post admin_sales_customer_invoices_path, params: {
      commit_action: "confirm",
      customer_invoice: { customer_id: customer.id, location_id: location.id,
        invoice_date: Date.current, customer_invoice_lines_attributes: line_attrs }
    }
    inv = CustomerInvoice.last
    expect(inv.status).to eq("confirmed")
    expect(customer.reload.ar_balance_cents).to eq(10_000)
    expect(ingredient.stock_batches.sum(:quantity_remaining).to_d).to eq(95)
    expect(response).to redirect_to(admin_sales_customer_invoice_path(inv))
  end

  it "collects a confirmed invoice by receipt voucher, not from the invoice page" do
    inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location, invoice_date: Date.current)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 2_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, owner).call
    treasury = Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 0, opening_balance_cents: 0, company: company)

    get admin_sales_customer_invoice_path(inv)
    expect(response.body).to include(
      ERB::Util.html_escape(new_admin_accounting_voucher_path(direction: Voucher::RECEIPT, settles: "CustomerInvoice:#{inv.id}"))
    )
    expect(response.body).not_to include("record_payment")

    post admin_accounting_vouchers_path, params: {
      voucher: { direction: Voucher::RECEIPT, treasury_id: treasury.id, amount_pounds: "40",
                 voucher_date: Date.current.to_s },
      settles: "CustomerInvoice:#{inv.id}"
    }

    expect(customer.reload.ar_balance_cents).to eq(6_000) # 10,000 - 4,000
    expect(treasury.reload.balance_cents).to eq(4_000)
    expect(inv.reload.amount_paid_cents).to eq(4_000)
    expect(inv.payment_status).to eq("partially_paid")
  end

  it "credits the sale to a chosen teammate (for their bonus)" do
    mate = create(:user, company: company, name: "Teammate")
    post admin_sales_customer_invoices_path, params: {
      commit_action: "draft",
      customer_invoice: { customer_id: customer.id, location_id: location.id, invoice_date: Date.current,
        salesperson_id: mate.id, customer_invoice_lines_attributes: line_attrs }
    }
    expect(CustomerInvoice.last.salesperson).to eq(mate)
    expect(CustomerInvoice.last.user).to eq(owner) # recorder is still the current user
  end

  it "defaults the salesperson to the recorder when none is chosen" do
    post admin_sales_customer_invoices_path, params: {
      commit_action: "draft",
      customer_invoice: { customer_id: customer.id, location_id: location.id, invoice_date: Date.current,
        customer_invoice_lines_attributes: line_attrs }
    }
    expect(CustomerInvoice.last.salesperson).to eq(owner)
  end

  it "is hidden for a restaurant company (feature off)" do
    company.update!(business_type: "restaurant")
    get admin_sales_customer_invoices_path
    expect(response).to redirect_to(admin_root_path)
  end
end
