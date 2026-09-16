# frozen_string_literal: true

require "rails_helper"

# A standing note belongs to the customer — an allergy, a gate code, "no coriander".
# Attaching them to an order copies it onto that order so the kitchen sees it
# without the cashier retyping it every time.
RSpec.describe "Customer standing notes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:menu_item) { create(:menu_item, company: company) }
  let(:customer) do
    create(:customer, company: company, name: "Nadia", phone: "01000000001",
                      standing_note: "Severe nut allergy")
  end

  before do
    Current.company = company
    # A single active branch is auto-selected by PosLocationScoped, and the item has
    # to be switched on there before the register will take it.
    LocationMenuItem.create!(location: branch, menu_item: menu_item, available: true)
    sign_in cashier
  end

  # Drives the real register flow: adding the first item is what creates the order
  # and puts it in the session, which is where every POS action looks for it.
  def start_cart!
    post pos_order_items_path, params: { menu_item_id: menu_item.id }
    Current.company = company
    Order.find(session[:current_order_id])
  end

  def attach!(**params)
    patch "/pos/attach_customer", params: params
    Current.company = company
  end

  describe "attaching a customer" do
    it "copies their standing note onto the order" do
      order = start_cart!

      attach!(customer_id: customer.id)

      expect(order.reload.notes).to eq("Severe nut allergy")
    end

    it "leaves a note the cashier already typed alone" do
      order = start_cart!
      order.update!(notes: "Table by the window")

      attach!(customer_id: customer.id)

      expect(order.reload.notes).to eq("Table by the window")
    end

    it "copies nothing when the customer has no standing note" do
      plain = create(:customer, company: company, name: "Walk-in", phone: "01000000002")
      order = start_cart!

      attach!(customer_id: plain.id)

      expect(order.reload.notes).to be_blank
    end

    it "ignores the legacy notes column the import filled with delivery landmarks" do
      customer.update!(notes: "above El-Ezaby pharmacy")
      order = start_cart!

      attach!(customer_id: customer.id)

      expect(order.reload.notes).to eq("Severe nut allergy")
    end
  end

  describe "clearing the customer" do
    it "takes the standing note back off" do
      order = start_cart!
      attach!(customer_id: customer.id)

      attach!(clear: "1")

      expect(order.reload.notes).to be_nil
    end

    it "keeps a note the cashier had edited" do
      order = start_cart!
      attach!(customer_id: customer.id)
      order.reload.update!(notes: "Severe nut allergy — and no dairy")

      attach!(clear: "1")

      expect(order.reload.notes).to eq("Severe nut allergy — and no dairy")
    end
  end

  describe "editing the note" do
    it "saves from the POS customer form" do
      # Reached only from inside the cart, and the response re-renders it.
      start_cart!
      attach!(customer_id: customer.id)

      patch pos_customer_path(customer), params: {
        customer: { name: "Nadia", standing_note: "Nut allergy, and no ice" }
      }

      expect(customer.reload.standing_note).to eq("Nut allergy, and no ice")
    end
  end
end
