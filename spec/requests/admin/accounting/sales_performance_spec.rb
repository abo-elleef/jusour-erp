# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting sales performance", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:branch) { create(:location, company: company, name: "Maadi") }

  before do
    Current.company = company
    sign_in owner
    order = create(:order, user: owner, company: company, location: branch, status: "completed",
                           subtotal_cents: 5000, total_cents: 5000, created_at: Time.current)
    order.order_events.create!(event_type: "refund", user: owner, description: "Refunded 700 cents: cold food")
  end

  it "renders each tab" do
    %w[branch cashier pickup exceptions].each do |tab|
      get admin_accounting_sales_performance_index_path(tab: tab, start_date: Date.current, end_date: Date.current)
      expect(response).to have_http_status(:ok)
    end
  end

  it "shows the branch row and links the refund to its order" do
    get admin_accounting_sales_performance_index_path(tab: "branch", start_date: Date.current, end_date: Date.current)
    expect(response.body).to include("Maadi")

    get admin_accounting_sales_performance_index_path(tab: "exceptions", start_date: Date.current, end_date: Date.current)
    expect(response.body).to include("cold food")
    expect(response.body).to include(admin_order_path(Order.first))
  end

  it "shows items per order for the branch, its order types and the total" do
    create(:order_item, order: Order.first, menu_item: create(:menu_item, company: company), quantity: 3)

    get admin_accounting_sales_performance_index_path(tab: "branch", start_date: Date.current, end_date: Date.current)

    page = Nokogiri::HTML(response.body)
    expect(page.at("[data-testid=items-per-order]").text.squish).to eq("3.0")
    expect(page.at("[data-testid=items-per-order-total]").text.squish).to eq("3.0")
    details = page.css("[data-testid=type-detail]").map { |e| e.text.squish }
    expect(details).to include(I18n.t("accounting.sales_performance.type_detail", count: 1, items: "3.0", locale: :ar))
  end

  it "ignores a bogus tab, kind and branch instead of failing" do
    get admin_accounting_sales_performance_index_path(tab: "nope", kind: "x", location_id: "not-a-uuid", sort: "bad")
    expect(response).to have_http_status(:ok)
  end

  it "is hidden from users without report access" do
    sign_in create(:user, company: company, role: "cashier")
    get admin_accounting_sales_performance_index_path
    expect(response).not_to have_http_status(:ok)
  end
end
