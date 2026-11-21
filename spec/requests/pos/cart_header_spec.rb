# frozen_string_literal: true

require "rails_helper"

# SAQR, 2026-11-21: the register forgot its cart. A background request (print
# polling, prefetch) that left before an add-item response came back wrote its
# older session cookie back, without the cart. The next item went into a new
# order, and picking the order type or customer started an empty one, leaving
# the basket behind as a draft. The register page now names its cart in the
# X-Pos-Cart header, and that wins over the session.
RSpec.describe "Register cart named by the page", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:item) do
    Current.company = company
    create(:menu_item, company: company, name: "Super Dinner", base_price_cents: 20_000).tap do |menu_item|
      create(:location_menu_item, location: branch, menu_item: menu_item, available: true)
    end
  end

  before do
    Current.company = company
    sign_in cashier
    open_drawer_for(cashier, location: branch)
    get pos_path # settles the branch in the session
  end

  def session_cookie_name
    Rails.application.config.session_options[:key]
  end

  # What a background request that started earlier does when it lands last.
  def put_back_stale_cookie(value)
    cookies[session_cookie_name] = value
  end

  def add_item(header: nil)
    headers = header.nil? ? {} : { PosCart::HEADER => header }
    post pos_order_items_path, params: { menu_item_id: item.id, quantity: "1" }, headers: headers, as: :turbo_stream
    Current.company = company
  end

  it "keeps adding to the page's cart when the session lost it" do
    stale = cookies[session_cookie_name]
    add_item(header: "")
    cart_id = response.headers[PosCart::HEADER]
    expect(cart_id).to be_present

    put_back_stale_cookie(stale)
    expect { add_item(header: cart_id) }.not_to change(Order, :count)

    expect(Order.find(cart_id).order_items.sum(:quantity)).to eq(2)
    expect(response.headers[PosCart::HEADER]).to eq(cart_id)
  end

  it "sets the order type and customer on the page's cart, not on a new empty one" do
    stale = cookies[session_cookie_name]
    add_item(header: "")
    cart_id = response.headers[PosCart::HEADER]

    put_back_stale_cookie(stale)
    expect {
      patch pos_update_fulfillment_path, params: { order_type: "delivery" },
                                         headers: { PosCart::HEADER => cart_id }, as: :turbo_stream
    }.not_to change(Order, :count)
    expect(Order.find(cart_id).order_type).to eq("delivery")

    put_back_stale_cookie(stale)
    expect {
      patch pos_attach_customer_path, params: { customer: { name: "Mona", phone: "01001234567" } },
                                      headers: { PosCart::HEADER => cart_id }, as: :turbo_stream
    }.not_to change(Order, :count)
    expect(Order.find(cart_id).customer&.name).to eq("Mona")
  end

  it "puts the session back on the page's cart, so the register shows it after a redirect" do
    stale = cookies[session_cookie_name]
    add_item(header: "")
    cart_id = response.headers[PosCart::HEADER]

    put_back_stale_cookie(stale)
    add_item(header: cart_id)
    get pos_path

    expect(response.body).to include(%(data-order-id="#{cart_id}"))
  end

  it "starts a new cart when the page's cart was placed in the meantime" do
    add_item(header: "")
    placed = Order.find(response.headers[PosCart::HEADER])
    placed.update!(status: "submitted")

    expect { add_item(header: placed.id) }.to change(Order, :count).by(1)
    expect(placed.reload.order_items.count).to eq(1)
  end

  it "lets New order leave the page's cart, and the register render follow the session" do
    add_item(header: "")
    cart_id = response.headers[PosCart::HEADER]

    post pos_new_order_path, headers: { PosCart::HEADER => cart_id }
    follow_redirect!(headers: { PosCart::HEADER => cart_id })

    expect(response.body).to include(%(id="pos-cart-ref" hidden data-order-id=""))
    expect(Order.find(cart_id).order_items.count).to eq(1) # a cart with food is kept
  end

  it "still follows the session when no page names a cart" do
    add_item
    cart_id = Order.order(:created_at).last.id

    expect { add_item }.not_to change(Order, :count)
    expect(Order.find(cart_id).order_items.sum(:quantity)).to eq(2)
  end
end
