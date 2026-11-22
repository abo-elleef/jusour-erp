# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Admin customers order counts and orders-date range", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:regular) { create(:customer, company: company, name: "Regular Rana", email: nil, phone: "01011111111") }
  let(:quiet) { create(:customer, company: company, name: "Quiet Qamar", email: nil, phone: "01022222222") }

  before do
    Current.company = company
    sign_in owner
  end

  def order_for(customer, date, total:, tip: 0, status: "completed")
    create(:order, user: owner, customer: customer, status: status, total_cents: total, tip_cents: tip,
           business_date: date, order_number: SecureRandom.hex(3))
  end

  it "shows every customer's all-time completed order count" do
    order_for(regular, Date.new(2026, 9, 5), total: 100_00)
    order_for(regular, Date.new(2026, 10, 5), total: 50_00)
    order_for(regular, Date.new(2026, 10, 6), total: 70_00, status: "cancelled")
    quiet

    get admin_customers_path, params: { sort: "orders_count", dir: "desc" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Regular Rana", "Quiet Qamar")
    expect(response.body.index("Regular Rana")).to be < response.body.index("Quiet Qamar")
  end

  it "with an orders range, lists only buyers in it with their orders and spend in that range" do
    order_for(regular, Date.new(2026, 9, 5), total: 100_00)
    order_for(regular, Date.new(2026, 10, 1), total: 50_00, tip: 5_00)
    order_for(regular, Date.new(2026, 10, 31), total: 30_00)
    order_for(quiet, Date.new(2026, 9, 10), total: 999_00)

    get admin_customers_path, params: { orders_from: "2026-10-01", orders_to: "2026-10-31" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Regular Rana", I18n.t("customers.table.period_orders"), I18n.t("customers.table.period_spend"))
    expect(response.body).not_to include("Quiet Qamar")
    # 2 orders in October, 45 + 30 = 75 (tips are not spend)
    expect(response.body).to include("75.00")
  end

  it "sorts by spend in the period" do
    order_for(regular, Date.new(2026, 10, 2), total: 10_00)
    order_for(quiet, Date.new(2026, 10, 3), total: 90_00)

    get admin_customers_path,
        params: { orders_from: "2026-10-01", orders_to: "2026-10-31", sort: "period_spent_cents", dir: "desc" }

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Quiet Qamar")).to be < response.body.index("Regular Rana")
  end

  it "adds the order columns to the CSV" do
    order_for(regular, Date.new(2026, 10, 2), total: 10_00)

    get admin_customers_path(format: :csv), params: { orders_from: "2026-10-01" }

    rows = CSV.parse(response.body)
    expect(rows.first).to include(I18n.t("customers.table.orders"), I18n.t("customers.table.period_orders"),
                              I18n.t("customers.table.period_spend"))
    expect(rows.size).to eq(2)
  end

  it "links each order on the customer's orders tab and shows its details" do
    order = create(:order, user: owner, customer: regular, status: "completed", order_type: "delivery",
                   delivery_address: "12 Nile St", total_cents: 80_00, discount_cents: 20_00,
                   business_date: Date.current, order_number: "77")
    order.order_discounts.create!(description: "Friday offer", amount_cents: 20_00)

    get admin_customer_path(regular, tab: "orders"), headers: { "Turbo-Frame" => "customer_tab" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_order_path(order), "12 Nile St", "Friday offer", "-20.00")
  end
end
