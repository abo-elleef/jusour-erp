# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting menu engineering", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:range) { { start_date: Date.current, end_date: Date.current } }

  before do
    Current.company = company
    sign_in owner
    ingredient = create(:ingredient, company: company, cost_per_unit_cents: 300)
    @burger = create(:menu_item, company: company, name: "Burger", base_price_cents: 1000)
    @tea = create(:menu_item, company: company, name: "Tea", base_price_cents: 500)
    Recipe.create!(menu_item: @burger, ingredient: ingredient, quantity_used: 1, unit: "kg")
    Recipe.create!(menu_item: @tea, ingredient: ingredient, quantity_used: 1, unit: "kg")
    order = create(:order, user: owner, company: company, location: branch, status: "completed",
                           subtotal_cents: 0, total_cents: 0, created_at: Time.zone.now.change(hour: 12))
    create(:order_item, order: order, menu_item: @burger, quantity: 8, unit_price_cents: 1000)
    create(:order_item, order: order, menu_item: @tea, quantity: 2, unit_price_cents: 500)
  end

  def rows
    Nokogiri::HTML(response.body).css("[data-testid=menu-engineering-row]").map { |tr| tr.css("td").map { |td| td.text.squish } }
  end

  it "lists each item with its class, linked to the item, with the chart and totals" do
    get admin_accounting_menu_engineering_index_path(range.merge(sort: "name", dir: "asc"))

    expect(response).to have_http_status(:ok)
    expect(rows.map(&:first)).to eq(%w[Burger Tea])
    star = I18n.t("accounting.menu_engineering.classes.star.name", locale: :ar)
    dog = I18n.t("accounting.menu_engineering.classes.dog.name", locale: :ar)
    expect(rows.map { |r| r[2] }).to eq([star, dog])
    expect(response.body).to include(admin_menu_item_path(@burger))
    expect(response.body).to include('data-testid="menu-engineering-chart"')
    expect(response.body).to include('data-testid="menu-engineering-totals"')
  end

  it "narrows to one class" do
    get admin_accounting_menu_engineering_index_path(range.merge(class: "dog"))
    expect(rows.map(&:first)).to eq(["Tea"])
  end

  it "exports CSV" do
    get admin_accounting_menu_engineering_index_path(range.merge(format: :csv, sort: "name", dir: "asc"))

    expect(response.media_type).to eq("text/csv")
    lines = CSV.parse(response.body)
    expect(lines.size).to eq(3)
    expect(lines[1].first(4)).to eq(["Burger", lines[1][1], I18n.t("accounting.menu_engineering.classes.star.name", locale: :ar), "8"])
  end

  it "is listed in the reports hub" do
    get admin_reports_path
    expect(response.body).to include(admin_accounting_menu_engineering_index_path)
  end

  it "is refused without the reports permission" do
    cashier = create(:user, company: company, wages_account_code: 2502)
    sign_in cashier
    get admin_accounting_menu_engineering_index_path(range)
    expect(response).to have_http_status(:redirect)
  end
end
