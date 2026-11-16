# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Live sales on the dashboard and the open-orders toggle", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:now) { Time.zone.local(2026, 11, 16, 14, 0) }

  before do
    Current.company = company
    sign_in owner
    item = create(:menu_item, company: company, name: "Burger", base_price_cents: 1000)
    open_order = create(:order, user: owner, company: company, status: "submitted",
                                subtotal_cents: 1000, total_cents: 1000, created_at: now - 1.hour)
    create(:order_item, order: open_order, menu_item: item, quantity: 1, unit_price_cents: 1000)
  end

  around { |ex| travel_to(now) { ex.run } }

  it "shows an order placed today on the dashboard before it is completed" do
    get admin_root_path
    expect(response).to have_http_status(:ok)
    live = response.body[/id="live-sales".*?<\/section>/m]
    expect(live).to include(I18n.t("dashboard.live.sales_so_far"))
    expect(live.gsub(/<[^>]+>/, " ")).to match(/10[.,٫]00|١٠[٫.]٠٠/)
  end

  it "leaves open orders out of the sales report unless asked to include them" do
    range = { start_date: Date.current, end_date: Date.current }

    get admin_accounting_sales_reports_path(range)
    expect(response.body).to include(I18n.t("accounting.sales_reports.include_open"))
    expect(response.body).not_to include("Burger")

    get admin_accounting_sales_reports_path(range.merge(include_open: "1"))
    expect(response.body).to include("Burger")
  end
end
