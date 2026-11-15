# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public self-ordering", type: :request do
  let(:company) { create(:company) }
  let(:branch) { online_branch(company) }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }
  let!(:area) { branch.delivery_areas.create!(company: company, name: "Dokki", fee_cents: 1_500) }
  let(:menu_path) { public_menu_path(company_slug: company.slug, location_slug: branch.slug) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
  end

  it "shows Add buttons and the checkout when the branch takes online orders" do
    get menu_path

    doc = Nokogiri::HTML(response.body)
    expect(doc.at("[data-controller~='online-order']")).to be_present
    expect(doc.at("button[data-action='online-order#open']")["data-item"]).to include(item.id)
    expect(doc.at("select[name='delivery_area_id']").text).to include("Dokki")
  end

  it "shows a closed note and no Add buttons when ordering is paused" do
    branch.update!(online_ordering_enabled: false)
    get menu_path
    expect(response.body).not_to include("online-order#open")

    branch.update!(online_ordering_enabled: true, online_open_time: "00:00", online_close_time: "00:01")
    get menu_path
    expect(response.body).to include(I18n.t("public.online_order.closed", locale: :en))
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
