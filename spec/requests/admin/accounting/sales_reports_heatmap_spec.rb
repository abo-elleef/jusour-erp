# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting sales report hour × weekday heatmap", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:menu_item) { create(:menu_item, company: company, name: "Burger", base_price_cents: 1000) }

  before do
    Current.company = company
    sign_in owner
  end

  def sale(at, cents)
    order = create(:order, user: owner, company: company, status: "completed",
                           subtotal_cents: cents, total_cents: cents, created_at: at)
    create(:order_item, order: order, menu_item: menu_item, quantity: 1, unit_price_cents: cents)
  end

  def grid(metric)
    table = Nokogiri::HTML(response.body).at("[data-testid=weekday-heatmap-#{metric}]")
    hours = table.css("thead th").map { |th| th.text.squish }[1..-2]
    rows = table.css("[data-testid=weekday-heatmap-row]").map { |tr| tr.css("td").map { |td| td.text.squish } }
    [hours, rows]
  end

  it "averages each weekday × hour over the weekdays in the range, Saturday first, trimmed to busy hours" do
    # Two Saturdays (14th, 21st) and two Sundays in the range; sales only on the 21st and 22nd.
    sale(Time.zone.local(2026, 11, 21, 13, 10), 1_000)
    sale(Time.zone.local(2026, 11, 21, 13, 40), 3_000)
    sale(Time.zone.local(2026, 11, 22, 15, 0), 2_000)

    get admin_accounting_sales_reports_path(start_date: "2026-11-14", end_date: "2026-11-27")

    expect(response).to have_http_status(:ok)
    hours, rows = grid("orders")
    expect(hours.size).to eq(3) # 13:00, 14:00, 15:00
    expect(rows.size).to eq(7)
    expect(rows[0]).to eq(["1", "", "", "1"])   # Saturday: 2 orders at 13:00 over 2 Saturdays
    expect(rows[1]).to eq(["", "", "0.5", "0.5"]) # Sunday
    expect(rows[2..].flatten.reject(&:empty?)).to eq(%w[0 0 0 0 0])

    _, sales = grid("sales")
    expect(sales[0].first).to eq("20") # 4,000 cents over 2 Saturdays = 20 a day
  end

  it "shows a tiny average as <0.1 rather than 0" do
    sale(Time.zone.local(2026, 11, 21, 13, 10), 1_000) # 1 order over 28 Saturdays
    get admin_accounting_sales_reports_path(start_date: "2026-05-09", end_date: "2026-11-21")
    _, rows = grid("orders")
    expect(rows[0].first).to eq("<0.1")
  end

  it "shows an empty note when nothing sold" do
    get admin_accounting_sales_reports_path(start_date: "2026-11-14", end_date: "2026-11-20")
    expect(response.body).to include(I18n.t("accounting.sales_reports.heatmap_empty", locale: :ar))
  end
end
