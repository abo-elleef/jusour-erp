# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Call center", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Downtown", call_center_enabled: true) }
  let(:other_branch) { create(:location, company: company, name: "Uptown", call_center_enabled: false) }
  let(:agent_role) { Role.create!(company: company, name: "Call center", key: "call_center", permissions: %w[orders:take_remote]) }
  let(:agent) { create(:user, company: company, role: "custom", role_id: agent_role.id, name: "Hoda", all_locations: true) }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
  end

  def order_json(**overrides)
    { order: online_params(item: item, **overrides).except(:website, :started_at).to_json }
  end

  context "as an agent" do
    before { sign_in agent }

    it "lands on the call center after sign-in and lists only branches that take call-center orders" do
      get root_path
      expect(response).to redirect_to(call_center_path)

      other_branch
      get call_center_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(new_call_center_order_path(branch))
      expect(response.body).not_to include(new_call_center_order_path(other_branch))
    end

    it "shows the branch menu wired to the call-center endpoints" do
      get new_call_center_order_path(branch)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Koshary")
      expect(response.body).to include(call_center_orders_path(branch))
    end

    it "refuses a branch that doesn't take call-center orders" do
      get new_call_center_order_path(other_branch)
      expect(response).to redirect_to(call_center_path)

      post call_center_orders_path(other_branch), params: order_json, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "sends the order as a call-center request and shows it in today's list, cancellable" do
      post call_center_orders_path(branch), params: order_json, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:created)
      req = OnlineOrderRequest.last
      expect(req).to have_attributes(channel: "call_center", created_by_id: agent.id, location_id: branch.id)
      expect(response.parsed_body["url"]).to eq(call_center_path(sent: req.token))

      get call_center_path(sent: req.token)
      expect(response.body).to include("Mona").and include(cancel_call_center_order_path(req.token))

      patch cancel_call_center_order_path(req.token)
      expect(req.reload).to be_cancelled
    end

    it "prices the cart" do
      post call_center_order_quote_path(branch), params: { items: [{ menu_item_id: item.id, quantity: 2 }] }, as: :json

      expect(response.parsed_body["total"]).to include("100")
    end
  end

  it "keeps out users without the permission" do
    sign_in create(:user, company: company, role: "cashier")

    get call_center_path
    expect(response).to redirect_to(root_path)
  end

  it "shows the branch cashier who sent a call-center order" do
    req = OnlineOrders::SubmitService.call(location: branch, staff: agent, params: online_params(item: item)).request
    cashier = create(:user, company: company, role: "cashier")
    sign_in cashier
    open_drawer_for(cashier, location: branch)
    get pos_path

    get pos_online_order_requests_path
    expect(response.body).to include(I18n.t("pos.online_orders.call_center_tag", agent: "Hoda", locale: :ar)).or include("Call center · Hoda")

    get pos_online_order_request_path(req)
    expect(response).to have_http_status(:ok)
  end
end
