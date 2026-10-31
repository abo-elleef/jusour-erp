# frozen_string_literal: true

require "rails_helper"

# The supplier page is a shell plus one lazily-loaded tab frame, and the
# statement of account is a tab of its own with a printable twin.
RSpec.describe "Supplier page tabs and statement of account", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company) }
  let!(:treasury) do
    Treasury.create!(name: "Main Safe", treasury_type: "safe", balance_cents: 1_000_000,
      opening_balance_cents: 1_000_000, company: company, active: true)
  end
  let(:ingredient) do
    Ingredient.create!(name: "Tomatoes", unit: "kg", reorder_threshold: 5, quantity_on_hand: 0,
      cost_per_unit_cents: 200, company: company,
      ingredient_category: IngredientCategory.create!(name: "Produce", position: 1, company: company))
  end

  before { sign_in owner }

  def invoice(total_cents, on:, number: "INV-#{on.strftime('%m%d')}-#{total_cents}")
    Current.company = company # a request in between resets it
    inv = VendorInvoice.new(supplier: supplier, user: owner, location: location,
      invoice_number: number, invoice_date: on, received_on: on, company: company)
    inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 1, line_total_cents: total_cents)
    inv.save!
    ::Accounting::SupplierApLedgerService.record_invoice!(invoice: inv, user: owner)
    inv
  end

  def pay(pounds, on: Date.current)
    post admin_accounting_vouchers_path, params: {
      voucher: { direction: Voucher::PAYMENT, treasury_id: treasury.id, amount_pounds: pounds,
                 voucher_date: on.to_s, party_selection: "Supplier:#{supplier.id}" },
      settles: Admin::Accounting::VouchersController::OLDEST_FIRST
    }
  end

  describe "the shell" do
    it "renders the header and stats with an empty, lazily-loading tab frame" do
      invoice(10_000, on: Date.current - 1)

      get admin_inventory_supplier_path(supplier)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fresh Farms")
      expect(response.body).to match(/<turbo-frame[^>]*id="supplier_tab"[^>]*src="[^"]*#{supplier.id}/)
      expect(response.body).to include(I18n.t("inventory.suppliers.show.tabs.loading"))
      # Tab content waits for the frame request.
      expect(response.body).not_to include(I18n.t("inventory.suppliers.show.overview.recent_invoices_heading"))
    end

    it "keeps the requested tab in the frame src so a reload lands on it" do
      get admin_inventory_supplier_path(supplier, tab: "statement")

      expect(response.body).to include("tab=statement")
    end

    it "counts every posted, non-void invoice rather than the first ten" do
      12.times { |i| invoice(1_000 + i, on: Date.current - i) }

      get admin_inventory_supplier_path(supplier)

      expect(response.body).to match(/>\s*12\s*<\/p>/)
    end
  end

  describe "tab frames" do
    it "opens on the overview when no tab is asked for" do
      get admin_inventory_supplier_path(supplier), headers: { "Turbo-Frame" => "supplier_tab" }

      expect(response.body).to include(I18n.t("inventory.suppliers.show.overview.recent_invoices_heading"))
      expect(response.body).to match(/<a[^>]*aria-current="page"[^>]*>#{I18n.t("inventory.suppliers.show.tabs.overview")}</)
    end

    it "falls back to the overview on an unknown tab" do
      get_supplier_tab(supplier, "nope")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("inventory.suppliers.show.overview.reorder_heading"))
    end

    it "sends links that leave the page to the top frame" do
      inv = invoice(10_000, on: Date.current - 1)

      get_supplier_tab(supplier, "overview")

      link = response.body[/<a[^>]*href="#{admin_inventory_vendor_invoice_path(inv)}"[^>]*>/]
      expect(link).to include('data-turbo-frame="_top"')
    end

    it "lists invoices with a status filter" do
      paid = invoice(10_000, on: Date.current - 10, number: "INV-PAID")
      invoice(20_000, on: Date.current - 1, number: "INV-OPEN")
      pay("100.00")
      expect(paid.reload.payment_status).to eq("paid")

      get_supplier_tab(supplier, "invoices")
      expect(response.body).to include("INV-PAID", "INV-OPEN")

      get_supplier_tab(supplier, "invoices", status: "open")
      expect(response.body).to include("INV-OPEN")
      expect(response.body).not_to include("INV-PAID")
    end

    it "sorts invoices by total" do
      invoice(10_000, on: Date.current - 2, number: "INV-SMALL")
      invoice(90_000, on: Date.current - 1, number: "INV-BIG")

      get_supplier_tab(supplier, "invoices", sort: "total", dir: "asc")

      expect(response.body.index("INV-SMALL")).to be < response.body.index("INV-BIG")
    end
  end

  describe "statement of account" do
    let(:start_date) { Date.current - 30 }

    before do
      invoice(10_000, on: start_date - 5, number: "INV-BEFORE")
      invoice(25_000, on: start_date + 2, number: "INV-INSIDE")
      pay("50.00", on: start_date + 4)
    end

    it "opens from the opening balance and runs to the AP balance" do
      result = ::Accounting::SupplierStatementService.new(
        supplier, start_date: start_date, end_date: Date.current
      ).call

      expect(result.opening_balance_cents).to eq(10_000)
      expect(result.rows.map(&:balance_cents)).to eq([35_000, 30_000])
      expect(result.total_increase_cents).to eq(25_000)
      expect(result.total_decrease_cents).to eq(5_000)
      expect(result.closing_balance_cents).to eq(supplier.ap_treasury.reload.balance_cents)
    end

    it "orders by date, not by when rows were recorded" do
      invoice(1_000, on: start_date + 1, number: "INV-BACKDATED")

      rows = ::Accounting::SupplierStatementService.new(
        supplier, start_date: start_date, end_date: Date.current
      ).call.rows

      expect(rows.map(&:occurred_on)).to eq(rows.map(&:occurred_on).sort)
      expect(rows.first.source.invoice_number).to eq("INV-BACKDATED")
      expect(rows.first.balance_cents).to eq(11_000)
    end

    it "includes invoices marked historical like any other" do
      inside = VendorInvoice.find_by!(invoice_number: "INV-INSIDE")
      inside.update_columns(historical_settled_cents: inside.total_cents, historical_settled_at: Time.current)

      rows = ::Accounting::SupplierStatementService.new(
        supplier, start_date: start_date, end_date: Date.current
      ).call.rows

      expect(rows.map { |r| r.source.try(:invoice_number) }).to include("INV-INSIDE")
    end

    it "renders in the statement tab within the chosen dates" do
      get_supplier_tab(supplier, "statement", start_date: start_date, end_date: Date.current)

      expect(response.body).to include("INV-INSIDE")
      expect(response.body).not_to include("INV-BEFORE")
      expect(response.body).to include(I18n.t("inventory.suppliers.statement.opening_balance"))
      expect(response.body).to include(statement_admin_inventory_supplier_path(supplier))
    end

    it "renders the printable page for the same range" do
      get statement_admin_inventory_supplier_path(supplier, start_date: start_date, end_date: Date.current)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("inventory.suppliers.statement.title", name: supplier.name))
      expect(response.body).to include("INV-INSIDE")
      expect(response.body).to include("window.print()")
    end

    it "swaps a reversed range instead of showing nothing" do
      get statement_admin_inventory_supplier_path(supplier, start_date: Date.current, end_date: start_date)

      expect(response.body).to include("INV-INSIDE")
    end

    it "is empty but still renders for a supplier with no AP history" do
      fresh = Supplier.create!(name: "Quiet Co", lead_time_days: 1, company: company)
      fresh.ap_treasury&.treasury_transactions&.delete_all

      get statement_admin_inventory_supplier_path(fresh)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("inventory.suppliers.statement.empty"))
    end
  end
end
