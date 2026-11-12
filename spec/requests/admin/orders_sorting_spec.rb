# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin orders table sorting", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:manager) { create(:user, :manager, company: company, name: "Mona") }
  let(:amir) { create(:user, company: company, role: "cashier", name: "Amir") }
  let(:zed) { create(:user, company: company, role: "cashier", name: "Zed") }
  let(:ann) { create(:customer, company: company, name: "Ann") }
  let(:bob) { create(:customer, company: company, name: "Bob") }

  before do
    Current.company = company
    sign_in manager
  end

  def make(user:, total:, items: 1, customer: nil, status: "completed", type: "pickup", at: Time.current)
    # Placed first (which numbers it), then moved to the status under test: a
    # cancelled order in this table was voided after it was placed.
    order = create(:order, user: user, customer: customer, company: company, location: branch,
                           status: "submitted", order_type: type, created_at: at)
    order.update!(status: status)
    items.times { create(:order_item, order: order, unit_price_cents: total / items) }
    order.recalculate_totals!
    order
  end

  def listed(**params)
    get admin_orders_path(params)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).css("tbody tr td:first-child a").map { |a| a.text.strip }
  end

  let!(:o1) { make(user: zed,  total: 3_000, items: 3, customer: bob, type: "delivery", at: 3.hours.ago) }
  let!(:o2) { make(user: amir, total: 1_000, items: 1, customer: nil, status: "submitted", type: "table", at: 2.hours.ago) }
  let!(:o3) { make(user: manager, total: 2_000, items: 2, customer: ann, status: "cancelled", at: 1.hour.ago) }

  it "shows newest first by default" do
    expect(listed).to eq([o3, o2, o1].map(&:order_number))
  end

  it "sorts by order number both ways" do
    expect(listed(sort: "order_number", dir: "asc")).to eq([o1, o2, o3].map(&:order_number))
    expect(listed(sort: "order_number", dir: "desc")).to eq([o3, o2, o1].map(&:order_number))
  end

  it "sorts by date" do
    expect(listed(sort: "created_at", dir: "asc")).to eq([o1, o2, o3].map(&:order_number))
  end

  it "sorts by cashier name" do
    expect(listed(sort: "cashier", dir: "asc")).to eq([o2, o3, o1].map(&:order_number)) # Amir, Mona, Zed
    expect(listed(sort: "cashier", dir: "desc")).to eq([o1, o3, o2].map(&:order_number))
  end

  it "sorts by customer and always puts orders without one last" do
    expect(listed(sort: "customer", dir: "asc")).to eq([o3, o1, o2].map(&:order_number)) # Ann, Bob, none
    expect(listed(sort: "customer", dir: "desc")).to eq([o1, o3, o2].map(&:order_number)) # Bob, Ann, none
  end

  it "sorts by type, status, item count and total" do
    expect(listed(sort: "order_type", dir: "asc").first).to eq(o1.order_number) # delivery
    expect(listed(sort: "status", dir: "asc")).to eq([o3, o1, o2].map(&:order_number)) # cancelled, completed, submitted
    expect(listed(sort: "items", dir: "desc")).to eq([o1, o3, o2].map(&:order_number)) # 3, 2, 1
    expect(listed(sort: "total", dir: "asc")).to eq([o2, o3, o1].map(&:order_number)) # 10, 20, 30
  end

  it "ignores a sort key or direction it does not know, instead of passing it to SQL" do
    expect(listed(sort: "total; DROP TABLE orders", dir: "sideways")).to eq([o3, o2, o1].map(&:order_number))
    expect(Order.count).to eq(3)
  end

  it "sorts within a filter and keeps the filter when sorting" do
    expect(listed(q: { status_in: nil, status_eq: "completed" }, sort: "total", dir: "asc")).to eq([o1.order_number])

    get admin_orders_path(q: { status_eq: "completed" }, sort: "total", dir: "asc", page: 1)
    link = Nokogiri::HTML(response.body).css("thead a").find { |a| a.text.include?(I18n.t("admin.orders.table.cashier")) }
    expect(link["href"]).to include("sort=cashier", "status_eq%5D=completed")
    expect(link["href"]).not_to include("page=")
  end

  it "marks the active column and flips direction on the next click" do
    get admin_orders_path(sort: "total", dir: "asc")
    total_link = Nokogiri::HTML(response.body).css("thead a").find { |a| a.text.include?("↑") }

    expect(total_link.text).to include(I18n.t("admin.orders.table.total"))
    expect(total_link["href"]).to include("sort=total", "dir=desc")
  end

  describe "pagination footer (same bar as vendor invoices)" do
    before { 49.times { make(user: amir, total: 500, at: 5.hours.ago) } } # 52 orders in all

    it "shows the range, 50 rows a page, and a second page that keeps the sort" do
      get admin_orders_path(sort: "total", dir: "asc")
      page = Nokogiri::HTML(response.body)

      expect(page.css("tbody tr").size).to eq(50)
      expect(page.text).to include(I18n.t("accounting.shared.pagination_showing", from: 1, to: 50, count: 52))
      next_link = page.css("nav a").find { |a| a.text.strip == I18n.t("actions.next") }
      expect(next_link["href"]).to include("page=2", "sort=total", "dir=asc")

      get admin_orders_path(sort: "total", dir: "asc", page: 2)
      expect(Nokogiri::HTML(response.body).css("tbody tr").size).to eq(2)
    end
  end
end

