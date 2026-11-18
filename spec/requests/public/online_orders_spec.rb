# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public self-ordering", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:branch) { online_branch(company) }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }
  let!(:area) { branch.delivery_areas.create!(company: company, name: "Dokki", fee_cents: 1_500) }
  let(:menu_path) { public_menu_path(company_slug: company.slug, location_slug: branch.slug) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
  end

  it "makes the whole card the tap target and shows the checkout when the branch takes online orders" do
    get menu_path

    doc = Nokogiri::HTML(response.body)
    expect(doc.at("[data-controller~='online-order']")).to be_present
    expect(doc.at(".public-menu-card button")).to be_nil
    card = doc.at("article.public-menu-card[role='button']")
    expect(card["data-action"]).to include("click->online-order#open")
    expect(card["data-item"]).to include(item.id)
    expect(doc.at("select[name='delivery_area_id']").text).to include("Dokki")
    expect(doc.at("[data-controller='recent-orders']")["data-recent-orders-storage-key-value"])
      .to eq("online-orders:#{company.slug}:#{branch.slug}")
  end

  it "gives the popup the full item price for every choice, not just the added amount" do
    group = ModifierGroup.create!(company: company, name: "Size")
    double = group.modifiers.create!(name: "Double", price_adjustment_cents: 3_500)
    item.menu_item_modifier_groups.create!(modifier_group: group, position: 1)

    get menu_path

    data = JSON.parse(Nokogiri::HTML(response.body).at("article.public-menu-card")["data-item"])
    expect(data["pricing"]["base_cents"]).to eq(5_000)
    expect(data["pricing"]["groups"].first["modifiers"])
      .to contain_exactly({ "id" => double.id, "price_adjustment_cents" => 3_500 })
    expect(data["groups"].first["modifiers"].first).not_to have_key("price")
  end

  it "shows a closed note and no Add buttons when ordering is paused" do
    branch.update!(online_ordering_enabled: false)
    get menu_path
    expect(response.body).not_to include("online-order#open")

    branch.update!(online_ordering_enabled: true, online_open_time: "00:00", online_close_time: "00:01")
    travel_to Time.find_zone(company.timezone.presence || Time.zone.name).parse("2026-11-17 12:00") do
      get menu_path
    end
    expect(response.body).not_to include("online-order#open")

    # The note sits above the menu and says when ordering opens.
    doc = Nokogiri::HTML(response.body)
    note = doc.at("#online-ordering-closed")
    expect(note.text).to include(I18n.t("public.online_order.closed", locale: :en))
    expect(note.text).to include("12:00 AM").and include("12:01 AM")
    expect(response.body.index("online-ordering-closed")).to be < response.body.index("public-menu-grid")
  end

  it "warns in the checkout quote when the total is over the online maximum" do
    branch.update!(online_max_order_cents: 10_000)
    quote_path = public_online_order_quote_path(company_slug: company.slug, location_slug: branch.slug)

    post quote_path, params: { items: [{ menu_item_id: item.id, quantity: 2 }], fulfillment: "pickup" }, as: :json
    expect(response.parsed_body["over_limit"]).to be_nil # exactly the max is allowed

    post quote_path, params: { items: [{ menu_item_id: item.id, quantity: 3 }], fulfillment: "pickup" }, as: :json
    expect(response.parsed_body["over_limit"]).to include("100")
  end

  it "quotes the cart from database prices" do
    post public_online_order_quote_path(company_slug: company.slug, location_slug: branch.slug),
         params: { items: [{ menu_item_id: item.id, quantity: 2 }], fulfillment: "delivery", delivery_area_id: area.id },
         as: :json

    body = response.parsed_body
    expect(body["total"]).to include("115")
    expect(body["errors"]).to be_empty
  end

  it "takes the order and shows a waiting status page" do
    post public_online_orders_path(company_slug: company.slug, location_slug: branch.slug),
         params: online_params(item: item, area: area), as: :json

    expect(response).to have_http_status(:created)
    request_record = OnlineOrderRequest.last
    expect(response.parsed_body["url"]).to end_with(request_record.token)

    get response.parsed_body["url"]
    expect(response.body).to include(I18n.t("public.online_order.status.pending", locale: :en))
    expect(response.body).to include("data-controller=\"auto-refresh\"")

    # The status page saves the order in the browser so the menu can link back to it.
    saved = Nokogiri::HTML(response.body).at("[data-recent-orders-mode-value='remember']")
    expect(saved["data-recent-orders-storage-key-value"]).to eq("online-orders:#{company.slug}:#{branch.slug}")
    expect(JSON.parse(saved["data-recent-orders-order-value"])).to include(
      "token" => request_record.token, "url" => response.request.path, "status" => "pending"
    )
  end

  it "explains a refusal in the customer's language" do
    post public_online_orders_path(company_slug: company.slug, location_slug: branch.slug),
         params: online_params(item: item, phone: "123"), as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("invalid_phone")
    expect(response.parsed_body["message"]).to be_present
  end

  it "shows the order number once accepted" do
    request_record = OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item)).request
    order = OnlineOrders::AcceptService.call(request: request_record, user: create(:user, company: company, role: "cashier")).order

    get public_online_order_path(company_slug: company.slug, token: request_record.token)

    expect(response.body).to include("##{order.order_number}")
    expect(response.body).not_to include("auto-refresh")
  end
end
