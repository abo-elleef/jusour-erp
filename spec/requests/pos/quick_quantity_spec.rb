# frozen_string_literal: true

require "rails_helper"

# Every menu item opens the add popup with a count field, so the cashier types the
# quantity when adding instead of fixing it in the cart afterwards.
RSpec.describe "POS quick quantity", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:item) { create(:menu_item, company: company, name: "Water", base_price_cents: 1_000) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
    sign_in cashier
    open_drawer_for(cashier, location: branch)
    get pos_path
  end

  def cart_lines
    Order.find(session[:current_order_id]).order_items.where(menu_item: item)
  end

  it "makes the whole card open the popup instead of adding the item straight away" do
    doc = Nokogiri::HTML(response.body)
    card = doc.at("a.menu-card[href='#{pos_modifier_form_path(menu_item_id: item.id)}']")

    expect(card).to be_present
    expect(card["data-turbo-frame"]).to eq("modifier_modal")
    expect(card.text).to include("Water")
    expect(card.css("a")).to be_empty
    expect(doc.at("form[action^='#{pos_order_items_path}'] input[name='menu_item_id'][value='#{item.id}']")).to be_nil
  end

  it "renders a focused count field defaulting to 1 in the popup for an item without modifiers" do
    get pos_modifier_form_path(menu_item_id: item.id)
    field = Nokogiri::HTML(response.body).at("input[name='quantity']")

    expect(field["value"]).to eq("1")
    expect(field["autofocus"]).to be_present
    expect(field["data-controller"]).to eq("arabic-numerals")
  end

  it "adds the typed count, and a second add of the same item merges into the line" do
    post pos_order_items_path, params: { menu_item_id: item.id, quantity: "3" }, as: :turbo_stream
    expect(cart_lines.sum(:quantity)).to eq(3)

    post pos_order_items_path, params: { menu_item_id: item.id, quantity: "3" }, as: :turbo_stream
    expect(cart_lines.count).to eq(1)
    expect(cart_lines.first.quantity).to eq(6)
  end

  it "treats a blank, zero or junk count as 1" do
    ["", "0", "abc"].each do |typed|
      post pos_order_items_path, params: { menu_item_id: item.id, quantity: typed }, as: :turbo_stream
    end

    expect(cart_lines.first.quantity).to eq(3)
  end
end
