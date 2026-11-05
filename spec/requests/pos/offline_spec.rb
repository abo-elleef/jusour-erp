# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POS offline mode", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Downtown") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:category) { create(:category, company: company, name: "Burgers") }
  let!(:burger) do
    create(:menu_item, company: company, category: category, name: "Burger", base_price_cents: 1000).tap do |item|
      LocationMenuItem.create!(location: branch, menu_item: item, available: true, price_override_cents: 1200)
    end
  end
  let!(:receipt_printer) do
    Printer.create!(company: company, location: branch, name: "Front", printer_type: "receipt",
                    connection_type: "network", host: "192.168.1.50", port: 9100, paper_width: "80mm", active: true)
  end
  let!(:kitchen_printer) do
    Printer.create!(company: company, location: branch, name: "Grill", printer_type: "kitchen", station: "Grill",
                    connection_type: "usb", host: "USB001", paper_width: "80mm", active: true).tap do |printer|
      PrinterMenuItem.create!(printer: printer, menu_item: burger)
    end
  end

  before do
    Current.company = company
    TaxRate.create!(company: company, name: "VAT", rate: 0.14, tax_category: "food", active: true)
  end

  context "when signed in as a cashier" do
    before do
      sign_in cashier
      patch pos_set_location_path, params: { location_id: branch.id }
    end

    it "serves the offline register shell with every label it needs" do
      get pos_offline_path

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include('data-controller="offline-pos"')
      expect(response.body).to include("fulfillment")
      # No Stripe, no websocket: both need the internet.
      expect(response.body).not_to include("js.stripe.com")
      expect(response.body).not_to include("turbo-cable-stream-source")
    end

    it "hands out a snapshot with the branch's menu, tax and printers" do
      get pos_offline_snapshot_path, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      item = body["menu"]["items"].sole
      expect(item).to include("name" => "Burger", "price_cents" => 1200, "tax_category" => "food")
      expect(body["menu"]["categories"].map { |c| c["name"] }).to eq(["Burgers"])
      expect(body["tax_rates"]).to eq([{ "tax_category" => "food", "rate" => "0.14" }])
      expect(body["user"]["id"]).to eq(cashier.id)
      expect(body["csrf_token"]).to be_present
      expect(body["agent"]).to include("url", "token")
      expect(body["printers"]["receipt"]).to include("host" => "192.168.1.50", "connection" => "network")
      station = body["printers"]["stations"].sole
      expect(station).to include("station" => "Grill", "connection" => "usb", "menu_item_ids" => [burger.id])
    end

    it "accepts an order and answers a repeat with the same order" do
      order_params = {
        client_uuid: SecureRandom.uuid, offline_number: "OFF-1", user_id: cashier.id, location_id: branch.id,
        order_type: "pickup", tendered_cents: 2000,
        items: [{ menu_item_id: burger.id, quantity: 1, unit_price_cents: 1200 }]
      }

      post pos_offline_orders_path, params: { order: order_params }, as: :json
      expect(response).to have_http_status(:created)
      first = response.parsed_body
      expect(first).to include("success" => true, "duplicate" => false)

      expect { post pos_offline_orders_path, params: { order: order_params }, as: :json }.not_to change(Order, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("duplicate" => true, "order_id" => first["order_id"])
    end

    it "explains a refusal instead of failing silently" do
      post pos_offline_orders_path, params: { order: { client_uuid: SecureRandom.uuid, items: [] } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  it "answers a signed-out snapshot request with 401, which the browser reads as 'sign in again'" do
    get pos_offline_snapshot_path, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "keeps the page away from people without POS access" do
    sign_in create(:user, company: company, role: "kitchen")

    get pos_offline_snapshot_path, as: :json
    expect(response).to have_http_status(:forbidden)

    post pos_offline_orders_path, params: { order: { client_uuid: SecureRandom.uuid } }, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
