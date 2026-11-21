# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin menu item show page", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let!(:location) { create(:location, company: company, name: "Downtown") }
  let!(:beef) { create(:ingredient, company: company, name: "Beef", unit: "kg", cost_per_unit_cents: 30_000) }
  let!(:sandwich) { create(:menu_item, company: company, name: "Old School", code: "SAN-001", base_price_cents: 10_000) }
  let!(:size) { ModifierGroup.create!(company: company, name: "Size", required: true) }
  let!(:double) { size.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 3_000) }
  let(:frame) { { "Turbo-Frame" => Admin::MenuItemsController::TAB_FRAME } }

  before do
    sign_in owner
    Recipe.create!(menu_item: sandwich, ingredient: beef, quantity_used: 0.1, unit: "kg")
    MenuItemModifierGroup.create!(menu_item: sandwich, modifier_group: size, position: 0)
    sandwich.location_menu_items.create!(location: location, available: true, price_override_cents: 12_000)
  end

  it "renders the shell with the tab frame" do
    get admin_menu_item_path(sandwich)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Old School", "SAN-001", %(id="#{Admin::MenuItemsController::TAB_FRAME}"))
  end

  it "shows the details, branches and option groups on Overview" do
    get admin_menu_item_path(sandwich), headers: frame
    text = Nokogiri::HTML(response.body).text.squish
    expect(text).to include("Downtown", "120.00", "Size", "Double (+30.00)")
  end

  it "shows the recipe and a read-only matrix on Recipe" do
    MenuItemModifierGroup.find_by(menu_item: sandwich, modifier_group: size).update!(recipe_matrix: true)
    get admin_menu_item_path(sandwich, tab: "recipe"), headers: frame
    doc = Nokogiri::HTML(response.body)
    expect(doc.text.squish).to include("Beef", "Double")
    expect(doc.css("#recipe-matrix form")).to be_empty
  end

  it "totals completed sales in the range and lists each line" do
    user = create(:user, company: company, wages_account_code: 2502)
    today = Date.current
    done = create(:order, user: user, company: company, location: location, status: "completed",
      business_date: today, subtotal_cents: 26_000, total_cents: 26_000)
    line = create(:order_item, order: done, menu_item: sandwich, quantity: 2, unit_price_cents: 10_000)
    line.order_item_modifiers.create!(modifier: double, name: "Double", price_adjustment_cents: 3_000)
    open_order = create(:order, user: user, company: company, location: location, status: "submitted",
      business_date: today, subtotal_cents: 10_000, total_cents: 10_000)
    create(:order_item, order: open_order, menu_item: sandwich, quantity: 1, unit_price_cents: 10_000)

    get admin_menu_item_path(sandwich, tab: "sales", from: today.iso8601, to: today.iso8601, sort: "amount"), headers: frame
    expect(response).to have_http_status(:ok)
    text = Nokogiri::HTML(response.body).text.squish
    expect(text).to include("260.00") # 2 × (100 + 30), the open order left out
    expect(Nokogiri::HTML(response.body).css("tbody tr").size).to eq(1)
  end

  it "shows the change history" do
    get admin_menu_item_path(sandwich, tab: "history"), headers: frame
    expect(response).to have_http_status(:ok)
  end

  it "links the item's name and code on the list to the show page" do
    get admin_menu_items_path
    links = Nokogiri::HTML(response.body).css(%(a[href="#{admin_menu_item_path(sandwich)}"])).map { |a| a.text.strip }
    expect(links).to include("Old School", "SAN-001")
  end
end
