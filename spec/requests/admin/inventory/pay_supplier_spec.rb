# frozen_string_literal: true

require "rails_helper"

# A supplier is paid by paying their invoices, and only by payment voucher. The
# old direct AP payment moved the AP balance without touching an invoice, which
# let the ledger and the invoice list drift apart; these specs pin the
# replacement shut.
RSpec.describe "Pay supplier", type: :request do
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

  # A posted invoice for `total_cents`, already on the supplier's AP ledger.
  def invoice(total_cents, on:)
    inv = VendorInvoice.new(supplier: supplier, user: owner, location: location,
      invoice_number: "INV-#{on.strftime('%m%d')}-#{total_cents}", invoice_date: on,
      received_on: on, company: company)
    inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 1, line_total_cents: total_cents)
    inv.save!
    ::Accounting::SupplierApLedgerService.record_invoice!(invoice: inv, user: owner)
    inv
  end

  def pay(pounds, treasury_id: treasury.id)
    post admin_accounting_vouchers_path, params: {
      voucher: { direction: Voucher::PAYMENT, treasury_id: treasury_id, amount_pounds: pounds,
                 voucher_date: Date.current.to_s, party_selection: "Supplier:#{supplier.id}" },
      settles: Admin::Accounting::VouchersController::OLDEST_FIRST
    }
  end

  describe "the supplier page" do
    let!(:open_invoice) { invoice(10_000, on: Date.current - 1) }

    it "links to a payment voucher instead of carrying its own payment form" do
      get admin_inventory_supplier_path(supplier)

      link = new_admin_accounting_voucher_path(direction: Voucher::PAYMENT, party: "Supplier:#{supplier.id}",
                                               settles: Admin::Accounting::VouchersController::OLDEST_FIRST)
      expect(response.body).to include(ERB::Util.html_escape(link))
      expect(response.body).not_to include("pay_supplier")
    end

    it "no longer routes a payment through the supplier" do
      expect { Rails.application.routes.recognize_path("/admin/inventory/suppliers/#{supplier.id}/pay_supplier", method: :post) }
        .to raise_error(ActionController::RoutingError)
    end

    it "opens the voucher with the supplier, oldest-first, and the open total filled in" do
      get new_admin_accounting_voucher_path(direction: Voucher::PAYMENT, party: "Supplier:#{supplier.id}",
                                            settles: Admin::Accounting::VouchersController::OLDEST_FIRST)

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/<option value="oldest_first" selected>/)
      expect(response.body).to match(/value="100\.0+"/)
    end
  end

  describe "oldest-first allocation" do
    let!(:oldest) { invoice(10_000, on: Date.current - 10) }
    let!(:middle) { invoice(20_000, on: Date.current - 5) }
    let!(:newest) { invoice(30_000, on: Date.current - 1) }

    it "closes whole invoices oldest first and leaves the newest untouched" do
      pay("300.00") # 30,000 cents — settles oldest + middle exactly

      expect(oldest.reload.payment_status).to eq("paid")
      expect(middle.reload.payment_status).to eq("paid")
      expect(newest.reload.payment_status).to eq("unpaid")
    end

    it "part-pays the invoice the money runs out on" do
      pay("150.00") # 15,000 cents

      expect(oldest.reload.payment_status).to eq("paid")
      expect(middle.reload.payment_status).to eq("partially_paid")
      expect(middle.balance_due_cents).to eq(15_000)
      expect(newest.reload.payment_status).to eq("unpaid")
    end

    it "keeps the AP ledger equal to what the open invoices still owe" do
      pay("150.00")

      open_due = supplier.vendor_invoices.posted.outstanding.sum { |i| i.balance_due_cents }
      expect(supplier.ap_treasury.reload.balance_cents).to eq(open_due)
    end

    it "takes the cash out of the chosen treasury once, not once per invoice total" do
      expect { pay("300.00") }.to change { treasury.reload.balance_cents }.by(-30_000)
    end

    it "records one voucher, with a line per invoice it settles" do
      expect { pay("150.00") }.to change(Voucher, :count).by(1)

      expect(Voucher.last.payment_allocations.map(&:settles)).to eq([oldest, middle])
    end

    it "refuses more than the open invoices come to, and writes nothing" do
      pay("700.00")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(oldest.reload.payment_status).to eq("unpaid")
      expect(treasury.reload.balance_cents).to eq(1_000_000)
    end

    it "refuses a zero amount" do
      expect { pay("0") }.not_to change(Voucher, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses an unknown treasury" do
      expect { pay("100.00", treasury_id: SecureRandom.uuid) }.not_to change(Voucher, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "with nothing open" do
    it "refuses the payment" do
      expect { pay("100.00") }.not_to change(Voucher, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "supplier AP ledger adjustments" do
    let!(:inv) { invoice(10_000, on: Date.current - 1) }

    it "refuses a hand adjustment on a supplier AP treasury" do
      ap = supplier.ap_treasury

      expect {
        post adjust_admin_accounting_treasury_path(ap), params: { amount_pounds: "-50", description: "x" }
      }.not_to change { ap.reload.balance_cents }

      expect(flash[:alert]).to eq(I18n.t("flash.accounting.treasury_ap_adjustment_blocked"))
    end

    it "still allows a hand adjustment on an ordinary treasury" do
      expect {
        post adjust_admin_accounting_treasury_path(treasury), params: { amount_pounds: "-50", description: "x" }
      }.to change { treasury.reload.balance_cents }.by(-5_000)
    end
  end
end
