# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::NotifyVendorBalanceNegativeJob, type: :job do
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: Current.company) }
  let(:invoice) do
    VendorInvoice.create!(supplier: supplier, user: create(:user), location: create(:location),
      invoice_number: "VI-TEST-1", invoice_date: Date.current, received_on: Date.current)
  end

  let!(:owner) { create(:user, :owner) }
  let!(:manager) { create(:user, role: "manager") }
  let!(:cashier) { create(:user, role: "cashier") }

  it "notifies owners and managers (not cashiers) with the invoice and balance" do
    expect {
      described_class.perform_now(supplier.id, invoice.id, -25_000)
    }.to change(Notification, :count).by(2)

    expect(Notification.where(recipient: cashier)).to be_empty

    note = Notification.find_by(recipient: owner)
    expect(note.notification_type).to eq("accounting")
    expect(note.params["message_key"]).to eq("vendor_balance_negative")
    params = note.params["message_params"]
    expect(params["supplier"]).to eq("Fresh Farms")
    expect(params["supplier_id"]).to eq(supplier.id)
    expect(params["balance_cents"]).to eq(-25_000)
    expect(params["invoice_number"]).to eq("VI-TEST-1")
    expect(params["vendor_invoice_id"]).to eq(invoice.id)
  end

  it "does nothing when the supplier no longer exists" do
    expect {
      described_class.perform_now("00000000-0000-0000-0000-000000000000", invoice.id, -1_000)
    }.not_to change(Notification, :count)
  end
end
