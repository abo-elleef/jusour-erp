# frozen_string_literal: true

require "rails_helper"

# The cashier types the delivery fee next to the address, or in the popup that
# Place order opens when the fee is still 0, so the payment modal is only needed
# when the money is actually taken.
RSpec.describe "Delivery fee without the payment modal", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:menu_item) { create(:menu_item, company: company) }
  let(:customer) { create(:customer, company: company, name: "Nadia", phone: "01000000001") }

  before do
    Current.company = company
    LocationMenuItem.create!(location: branch, menu_item: menu_item, available: true)
    customer.addresses.create!(address: "12 Nile St", is_default: true)
    sign_in cashier
    open_drawer_for(cashier, location: branch)
  end

  def fulfillment(**params)
    patch pos_update_fulfillment_path, params: params, headers: turbo_headers
    Current.company = company
  end

  def start_delivery_cart!
    post pos_order_items_path, params: { menu_item_id: menu_item.id }
    Current.company = company
    order = Order.find(session[:current_order_id])
    patch "/pos/attach_customer", params: { customer_id: customer.id }, headers: turbo_headers
    fulfillment(order_type: "delivery")
    order.reload
  end

  describe "the field next to the address" do
    it "saves the fee into the total and re-renders the cart and the modal" do
      order = start_delivery_cart!
      food = order.total_cents

      fulfillment(order_type: "delivery", delivery_address: "12 Nile St", delivery_fee_pounds: "25")

      order.reload
      expect(order.delivery_fee_cents).to eq(2_500)
      expect(order.total_cents).to eq(food + 2_500)
      expect(response.body).to include('target="cart"')
      expect(response.body).to include('target="payment-modal-content"')
    end

    it "accepts a blank fee as free delivery" do
      order = start_delivery_cart!
      fulfillment(order_type: "delivery", delivery_address: "12 Nile St", delivery_fee_pounds: "25")
      fulfillment(order_type: "delivery", delivery_address: "12 Nile St", delivery_fee_pounds: "")

      expect(order.reload.delivery_fee_cents).to eq(0)
    end

    it "refuses a negative fee" do
      order = start_delivery_cart!
      fulfillment(order_type: "delivery", delivery_address: "12 Nile St", delivery_fee_pounds: "-5")

      expect(order.reload.delivery_fee_cents).to eq(0)
      expect(response.body).to include(I18n.t("flash.pos.negative_delivery_fee"))
    end

    it "drops the fee when the order is switched away from delivery" do
      order = start_delivery_cart!
      fulfillment(order_type: "delivery", delivery_address: "12 Nile St", delivery_fee_pounds: "25")
      fulfillment(order_type: "pickup", delivery_fee_pounds: "25")

      order.reload
      expect(order).to be_pickup
      expect(order.delivery_fee_cents).to eq(0)
    end

    it "picks Delivery on an empty cart without an error" do
      fulfillment(order_type: "delivery")

      expect(response).to have_http_status(:ok)
      expect(Order.find(session[:current_order_id])).to be_delivery
      expect(response.body).to include('target="cart"')
    end

    it "shows the field in the delivery section" do
      start_delivery_cart!
      expect(response.body).to include('id="fulfillment_delivery_fee_pounds"')
    end
  end

  describe "Place order" do
    it "opens the fee popup while a delivery order has no fee" do
      start_delivery_cart!
      expect(response.body).to include('id="place-order-fee-dialog"')
    end

    it "places the order directly once the fee is set" do
      start_delivery_cart!
      fulfillment(order_type: "delivery", delivery_address: "12 Nile St", delivery_fee_pounds: "25")
      expect(response.body).not_to include('id="place-order-fee-dialog"')
    end

    it "saves the fee typed in the popup and places the order" do
      order = start_delivery_cart!
      food = order.total_cents

      patch pos_submit_path, params: { delivery_fee_pounds: "30" }

      order.reload
      expect(order.status).not_to eq("draft")
      expect(order.delivery_fee_cents).to eq(3_000)
      expect(order.amount_due_cents).to eq(food + 3_000)
      expect(order.delivery_fee_drawer_session).to be_nil
    end

    it "places a free delivery when the popup is left empty" do
      order = start_delivery_cart!
      patch pos_submit_path, params: { delivery_fee_pounds: "" }

      order.reload
      expect(order.status).not_to eq("draft")
      expect(order.delivery_fee_cents).to eq(0)
    end

    it "refuses a negative fee and keeps the order in the register" do
      order = start_delivery_cart!
      patch pos_submit_path, params: { delivery_fee_pounds: "-5" }

      expect(order.reload.status).to eq("draft")
      expect(flash[:alert]).to eq(I18n.t("flash.pos.negative_delivery_fee"))
    end
  end

  describe "the delivery area dropdown" do
    let!(:zamalek) { DeliveryArea.create!(company: company, location: branch, name: "Zamalek", name_ar: "الزمالك", fee_cents: 3_000) }

    def area_picker
      Nokogiri::HTML(response.body).at("[data-testid=delivery-area-picker]")
    end

    def area_options
      JSON.parse(area_picker["data-searchable-select-options"])
    end

    def picked_area_id
      area_picker.at("#fulfillment_delivery_area_id")["value"]
    end

    it "is hidden on a branch with no active areas" do
      zamalek.update!(active: false)
      start_delivery_cart!
      expect(area_picker).to be_nil
      expect(response.body).to include('id="fulfillment_delivery_fee_pounds"')
    end

    it "lists the branch's active areas with their fee for the browser to fill in" do
      start_delivery_cart!
      DeliveryArea.create!(company: company, location: branch, name: "Old zone", fee_cents: 1_000, active: false)
      other = create(:location, company: company, name: "Other Branch")
      DeliveryArea.create!(company: company, location: other, name: "Maadi", fee_cents: 5_000)

      fulfillment(order_type: "delivery", delivery_address: "12 Nile St")

      expect(area_options.map { |o| o["value"] }).to eq([zamalek.id])
      expect(area_options.first["label"]).to start_with(zamalek.display_name)
      expect(area_options.first["fee"]).to eq("30.00")
      expect(response.body).not_to include("Maadi")
      expect(response.body).not_to include("Old zone")
    end

    it "lets the cashier search by the English or the Arabic name" do
      start_delivery_cart!
      expect(area_options.first["keywords"]).to include("Zamalek", "الزمالك")
    end

    it "clears the area and keeps the typed fee when the search box is emptied" do
      order = start_delivery_cart!
      fulfillment(order_type: "delivery", delivery_area_id: zamalek.id, delivery_fee_pounds: "30")
      fulfillment(order_type: "delivery", delivery_area_id: "", delivery_fee_pounds: "30")

      order.reload
      expect(order.delivery_area).to be_nil
      expect(order.delivery_fee_cents).to eq(3_000)
    end

    it "saves the area with the fee the field carries, so the cashier can change it" do
      order = start_delivery_cart!
      food = order.total_cents

      fulfillment(order_type: "delivery", delivery_address: "12 Nile St", delivery_area_id: zamalek.id, delivery_fee_pounds: "35")

      order.reload
      expect(order.delivery_area).to eq(zamalek)
      expect(order.delivery_fee_cents).to eq(3_500)
      expect(order.total_cents).to eq(food + 3_500)
      expect(picked_area_id).to eq(zamalek.id)
    end

    it "refuses another branch's area and leaves the order as it was" do
      order = start_delivery_cart!
      other = create(:location, company: company, name: "Other Branch")
      maadi = DeliveryArea.create!(company: company, location: other, name: "Maadi", fee_cents: 5_000)

      fulfillment(order_type: "delivery", delivery_area_id: maadi.id, delivery_fee_pounds: "50")

      order.reload
      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.delivery_area).to be_nil
      expect(order.delivery_fee_cents).to eq(0)
    end

    it "clears the area when the order is switched away from delivery" do
      order = start_delivery_cart!
      fulfillment(order_type: "delivery", delivery_area_id: zamalek.id, delivery_fee_pounds: "30")
      fulfillment(order_type: "pickup")

      order.reload
      expect(order.delivery_area).to be_nil
      expect(order.delivery_fee_cents).to eq(0)
    end

    it "lets Place order go straight through once a free area is picked" do
      free = DeliveryArea.create!(company: company, location: branch, name: "Next door", fee_cents: 0)
      start_delivery_cart!
      expect(response.body).to include('id="place-order-fee-dialog"')

      fulfillment(order_type: "delivery", delivery_area_id: free.id, delivery_fee_pounds: "0.00")
      expect(response.body).not_to include('id="place-order-fee-dialog"')
    end

    it "keeps an area that was switched off since listed on the order that has it" do
      order = start_delivery_cart!
      fulfillment(order_type: "delivery", delivery_area_id: zamalek.id, delivery_fee_pounds: "30")
      zamalek.update!(active: false)

      fulfillment(order_type: "delivery", delivery_address: "12 Nile St")

      expect(order.reload.delivery_area).to eq(zamalek)
      expect(picked_area_id).to eq(zamalek.id)
    end
    describe "in the Place order fee popup" do
      def popup
        Nokogiri::HTML(response.body).at("#place-order-fee-dialog")
      end

      it "offers the searchable area list with each area's fee" do
        start_delivery_cart!
        picker = popup.at("[data-testid=place-order-area-picker]")
        options = JSON.parse(picker["data-searchable-select-options"])
        expect(options.map { |o| [o["value"], o["fee"]] }).to eq([[zamalek.id, "30.00"]])
        expect(popup.at("#place_order_delivery_fee_pounds")["data-delivery-area-fee-target"]).to eq("fee")
      end

      it "shows only the fee box on a branch with no areas" do
        zamalek.update!(active: false)
        start_delivery_cart!
        expect(popup.at("[data-testid=place-order-area-picker]")).to be_nil
        expect(popup.at("#place_order_delivery_fee_pounds")).to be_present
      end

      it "saves the picked area and the fee, then places the order" do
        order = start_delivery_cart!
        food = order.total_cents

        patch pos_submit_path, params: { delivery_area_id: zamalek.id, delivery_fee_pounds: "30.00" }

        order.reload
        expect(order.status).not_to eq("draft")
        expect(order.delivery_area).to eq(zamalek)
        expect(order.delivery_fee_cents).to eq(3_000)
        expect(order.amount_due_cents).to eq(food + 3_000)
      end

      it "refuses an area that is not this branch's and keeps the order in the register" do
        order = start_delivery_cart!
        other = create(:location, company: company, name: "Other Branch")
        maadi = DeliveryArea.create!(company: company, location: other, name: "Maadi", fee_cents: 5_000)

        patch pos_submit_path, params: { delivery_area_id: maadi.id, delivery_fee_pounds: "50" }

        order.reload
        expect(order.status).to eq("draft")
        expect(order.delivery_area).to be_nil
        expect(order.delivery_fee_cents).to eq(0)
        expect(flash[:alert]).to be_present
      end

      it "refuses an area id that does not exist" do
        order = start_delivery_cart!
        patch pos_submit_path, params: { delivery_area_id: SecureRandom.uuid, delivery_fee_pounds: "50" }

        expect(order.reload.status).to eq("draft")
        expect(flash[:alert]).to be_present
      end
    end
  end
end
