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
    %w[branch cashier exceptions].each do |tab|
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
