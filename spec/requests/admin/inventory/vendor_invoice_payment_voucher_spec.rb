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

  it "records the payment through the controller and marks the invoice paid" do
    post record_payment_admin_inventory_vendor_invoice_path(invoice),
         params: { treasury_id: treasury.id, payment_amount_dollars: "50.00",
                   payment_date: Date.current.to_s }

    expect(invoice.reload.payment_status).to eq("paid")
    expect(invoice.payment_vouchers.count).to eq(1)
    expect(treasury.reload.balance_cents).to eq(95_000)
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
