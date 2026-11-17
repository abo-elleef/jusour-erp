# frozen_string_literal: true

require "rails_helper"

# The "Most sold" row on the register: this branch's best sellers, using the same
# cards (price, promo) as the full menu, and only items still sold here.
RSpec.describe "POS most sold row", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch", pos_top_sellers_enabled: true) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:burger) { create(:menu_item, company: company, name: "Top Burger") }
  let(:retired) { create(:menu_item, company: company, name: "Retired Wrap") }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: burger, available: true)
    create(:location_menu_item, location: branch, menu_item: retired, available: false)
    [burger, retired].each do |item|
      order = create(:order, user: cashier, location: branch, status: "completed", placed_at: 1.day.ago)
      create(:order_item, order: order, menu_item: item, quantity: 3)
    end
    sign_in cashier
    open_drawer_for(cashier, location: branch)
  end

  def row
    get pos_path
    Nokogiri::HTML(response.body).at("[data-pos-target='topSellersSection']")
  end

  it "shows the branch's top sellers that are still available here" do
    expect(row.text).to include("Top Burger")
    expect(row.text).not_to include("Retired Wrap")
  end

  it "is left out when the branch has it turned off" do
    branch.update!(pos_top_sellers_enabled: false)
    expect(row).to be_nil
  end

  it "is left out when the branch has sold nothing completed" do
    Order.where(location: branch).update_all(status: "cancelled")
    expect(row).to be_nil
  end
end
