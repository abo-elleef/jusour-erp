# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::NotifyPriceChangeJob, type: :job do
  let(:category) { create(:ingredient_category) }
  let(:ingredient) { create(:ingredient, ingredient_category: category, name: "Tomatoes") }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: Current.company) }
  let(:invoice) do
    VendorInvoice.create!(supplier: supplier, user: create(:user), location: create(:location),
      invoice_number: "VI-TEST-1", invoice_date: Date.current, received_on: Date.current)
  end

  let!(:owner) { create(:user, :owner) }
  let!(:manager) { create(:user, role: "manager") }
  let!(:cashier) { create(:user, role: "cashier") }

  it "notifies owners and managers (not cashiers) with the price-change details" do
    expect {
      described_class.perform_now(ingredient.id, supplier.id, 200, 250, invoice.id)
    }.to change(Notification, :count).by(2)

    expect(Notification.where(recipient: cashier)).to be_empty

    note = Notification.find_by(recipient: owner)
    expect(note.notification_type).to eq("inventory")
    expect(note.params["message_key"]).to eq("price_change")
    params = note.params["message_params"]
    expect(params["name"]).to eq("Tomatoes")
    expect(params["supplier"]).to eq("Fresh Farms")
    expect(params["old_price_cents"]).to eq(200)
    expect(params["new_price_cents"]).to eq(250)
    expect(params["percent"].to_f).to eq(25.0)
    expect(params["direction"]).to eq("up")
    expect(params["invoice_number"]).to eq("VI-TEST-1")
  end

  it "reports a drop with a downward direction" do
    described_class.perform_now(ingredient.id, supplier.id, 200, 150, invoice.id)

    params = Notification.find_by(recipient: owner).params["message_params"]
    expect(params["direction"]).to eq("down")
    expect(params["percent"].to_f).to eq(25.0)
  end

  it "does nothing when the baseline price is zero" do
    expect {
      described_class.perform_now(ingredient.id, supplier.id, 0, 250, invoice.id)
    }.not_to change(Notification, :count)
  end
end
