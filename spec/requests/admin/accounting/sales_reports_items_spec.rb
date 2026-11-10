# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting sales report items view", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:mains) { create(:category, company: company, name: "Mains") }
  let(:drinks) { create(:category, company: company, name: "Drinks") }

  before do
    Current.company = company
    sign_in owner
    burger = create(:menu_item, company: company, category: mains, name: "Burger", base_price_cents: 1000)
    cola = create(:menu_item, company: company, category: drinks, name: "Cola", base_price_cents: 300)
    order = create(:order, user: owner, company: company, status: "completed",
                           subtotal_cents: 2300, total_cents: 2300, created_at: Time.current)
    create(:order_item, order: order, menu_item: burger, quantity: 2, unit_price_cents: 1000)
    create(:order_item, order: order, menu_item: cola, quantity: 1, unit_price_cents: 300)
  end

  let(:range) { { start_date: Date.current, end_date: Date.current } }

  it "shows the items table" do
    get admin_accounting_sales_reports_path(range)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Burger", "Cola")
  end

  it "filters by category" do
    get admin_accounting_sales_reports_path(range.merge(item_category: "Drinks"))
    section = response.body[/id="items-sold".*?<\/section>/m]
    expect(section).to include("Cola")
    expect(section).not_to include("Burger")
  end

  it "sorts, and ignores an unknown sort key or category" do
    get admin_accounting_sales_reports_path(range.merge(sort: "name", dir: "asc"))
    section = response.body[/id="items-sold".*?<\/section>/m]
    expect(section.index("Burger")).to be < section.index("Cola")

    get admin_accounting_sales_reports_path(range.merge(sort: "x; DROP", item_category: "nope"))
    expect(response).to have_http_status(:ok)
  end

  it "includes the items in the CSV export" do
    get admin_accounting_sales_reports_path(range.merge(format: :csv))
    expect(response.body).to include("Burger,Mains,2")
  end
end
