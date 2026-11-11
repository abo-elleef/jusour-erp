# frozen_string_literal: true

require "rails_helper"

# The customize modal shows the whole item price for each choice, so the
# cashier never adds "+35" in their head.
RSpec.describe "POS customize modal prices", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:item) { create(:menu_item, company: company, name: "Old School", base_price_cents: 10_000) }
  let(:size) { ModifierGroup.create!(company: company, name: "Size", required: true) }
  let(:temp) { ModifierGroup.create!(company: company, name: "Hot or cold", required: true) }
  let(:single) { size.modifiers.create!(name: "Single", price_adjustment_cents: 0) }
  let(:double) { size.modifiers.create!(name: "Double", price_adjustment_cents: 3_500) }
  let(:hot) { temp.modifiers.create!(name: "Hot", price_adjustment_cents: 0) }

  before do
    Current.company = company
    # A branch price different from the company base price.
    create(:location_menu_item, location: branch, menu_item: item, available: true, price_override_cents: 11_000)
    item.menu_item_modifier_groups.create!(modifier_group: temp, position: 1)
    item.menu_item_modifier_groups.create!(modifier_group: size, position: 2)
    [single, double, hot]
    sign_in cashier
    open_drawer_for(cashier, location: branch)
    get pos_path
  end

  def modal
    get pos_modifier_form_path(menu_item_id: item.id)
    Nokogiri::HTML(response.body)
  end

  it "shows each size's full price at the branch, and no prices for choices that cost nothing" do
    doc = modal
    config = JSON.parse(doc.at("form[data-controller='modifier-pricing']")["data-modifier-pricing-config-value"])

    expect(config["base_cents"]).to eq(11_000)
    expect(doc.at("[data-modifier-price='#{single.id}']").text).to include("110.00")
    expect(doc.at("[data-modifier-price='#{double.id}']").text).to include("145.00")
    expect(doc.at("[data-modifier-price='#{hot.id}']")).to be_nil
  end

  it "sends live promos in priority order so the modal can show promo prices" do
    create(:menu_promo, company: company, menu_item: item, modifier: double, promo_price_cents: 13_000)

    config = JSON.parse(modal.at("form[data-controller='modifier-pricing']")["data-modifier-pricing-config-value"])

    expect(config["promos"]).to eq([{ "modifier_id" => double.id, "discount_cents" => 1_500 }])
  end
end
