# frozen_string_literal: true

require "rails_helper"

# Paying a supplier invoice issues a payment voucher. The invoice page has to
# render those, and reversing one has to void the voucher — nothing rendered
# this section with a payment on it before, which is how `payment.payment_date`
# survived the change to vouchers.
RSpec.describe "Paying a supplier invoice", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company)  { Current.company }
  let(:owner)    { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company) }
  let(:treasury) do
    Treasury.create!(name: "Main Safe", treasury_type: "safe", opening_balance_cents: 100_000,
                     balance_cents: 100_000, company: company)
  end
  let(:ingredient) do
    create(:ingredient, company: company,
           ingredient_category: create(:ingredient_category, company: company),
           name: "Tomatoes", unit: "kg")
  end
  let(:invoice) do
    inv = VendorInvoice.new(supplier: supplier, user: owner, location: location,
                            invoice_number: "INV-9100", invoice_date: Date.current,
                            received_on: Date.current, company: company)
    inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 10, line_total_cents: 5_000)
    inv.save!
    Accounting::SupplierApLedgerService.record_invoice!(invoice: inv, user: owner)
    inv.reload
  end

  before { sign_in owner }

  def pay!(amount_cents)
    Accounting::RecordVendorInvoicePaymentService.new(
      vendor_invoice: invoice, user: owner, treasury: treasury,
      amount_cents: amount_cents, payment_date: Date.current
    ).call
  end

  it "shows the voucher on the invoice page, with a link to the document" do
    voucher = pay!(5_000)

    get admin_inventory_vendor_invoice_path(invoice)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(voucher.number)
    expect(response.body).to include(admin_accounting_voucher_path(voucher))
  end

  def issue_voucher(amount:, settles: "VendorInvoice:#{invoice.id}", party: nil)
    post admin_accounting_vouchers_path, params: {
      voucher: { direction: Voucher::PAYMENT, treasury_id: treasury.id, amount_pounds: amount,
                 voucher_date: Date.current.to_s, party_selection: party },
      settles: settles
    }
  end

  it "links the invoice page to a payment voucher instead of a payment form" do
    get admin_inventory_vendor_invoice_path(invoice)

    voucher_link = new_admin_accounting_voucher_path(direction: Voucher::PAYMENT, settles: "VendorInvoice:#{invoice.id}")
    expect(response.body).to include(ERB::Util.html_escape(voucher_link))
    expect(response.body).not_to include("record_payment")
  end

  it "no longer routes a payment through the invoice" do
    expect { Rails.application.routes.recognize_path("/admin/inventory/vendor_invoices/#{invoice.id}/record_payment", method: :post) }
      .to raise_error(ActionController::RoutingError)
  end

  it "opens the voucher with the invoice, its balance and its supplier filled in" do
    get new_admin_accounting_voucher_path(direction: Voucher::PAYMENT, settles: "VendorInvoice:#{invoice.id}")

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/<option value="VendorInvoice:#{invoice.id}" selected>/)
    expect(response.body).to include('value="50.00"').or include('value="50.0"')
  end

  it "pays the invoice from the voucher form and marks it paid" do
    issue_voucher(amount: "50.00")

    expect(invoice.reload.payment_status).to eq("paid")
    expect(invoice.payment_vouchers.count).to eq(1)
    expect(treasury.reload.balance_cents).to eq(95_000)
    expect(supplier.ap_treasury.reload.balance_cents).to be_zero
  end

  it "refuses to settle more than the invoice still owes" do
    expect { issue_voucher(amount: "60.00") }.not_to change { invoice.reload.amount_paid_cents }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(treasury.reload.balance_cents).to eq(100_000)
  end

  it "refuses a voucher whose party is a different supplier" do
    other = Supplier.create!(name: "Other Farms", lead_time_days: 2, company: company)

    expect { issue_voucher(amount: "50.00", party: "Supplier:#{other.id}") }
      .not_to change { invoice.reload.amount_paid_cents }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "gives everything back when the payment is reversed" do
    voucher = pay!(5_000)
    expect(treasury.reload.balance_cents).to eq(95_000)

    delete admin_inventory_vendor_invoice_vendor_invoice_payment_path(invoice, voucher)

    expect(voucher.reload).to be_voided
    expect(treasury.reload.balance_cents).to eq(100_000)
    expect(invoice.reload.amount_paid_cents).to eq(0)
    expect(invoice.payment_status).to eq("unpaid")
    expect(supplier.ap_treasury.reload.balance_cents).to eq(5_000)
  end

  it "renders the page when the invoice has no payments yet" do
    invoice
    get admin_inventory_vendor_invoice_path(invoice)
    expect(response).to have_http_status(:ok)
  end
end
