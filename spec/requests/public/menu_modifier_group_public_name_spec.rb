# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public menu modifier group names", type: :request do
  include ApplicationHelper
  include PosModifierHelper
  include PublicOrderingHelper

  let(:company) { create(:company, slug: "acme-cafe") }
  let!(:branch) do
    create(:location, company: company, name: "Downtown", slug: "downtown", location_type: "branch",
      active: true, public_menu_enabled: true)
  end
  let!(:category) { create(:category, company: company, name: "Mains") }
  let!(:menu_item) do
    create(:menu_item, company: company, category: category, name: "Burger", base_price_cents: 1500, available: true)
  end
  let!(:group) { ModifierGroup.create!(company: company, name: "حار/عادي", public_name: "Hot level") }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: menu_item, available: true)
    group.modifiers.create!(company: company, name: "Hot", position: 0)
    MenuItemModifierGroup.create!(menu_item: menu_item, modifier_group: group, position: 0)
  end

  it "does not list modifier groups or their options on the menu card" do
    get public_menu_path(company_slug: company.slug, location_slug: branch.slug)

    expect(response.body).not_to include("Hot level:")
    expect(response.body).not_to include("حار/عادي")
  end

  it "uses the public name in the order popup data" do
    json = JSON.parse(orderable_item_json(menu_item.reload, branch))
    expect(json["groups"].first["name"]).to eq("Hot level")
  end

  it "falls back to the cashier name in the popup when no public name is set" do
    group.update!(public_name: "")

    json = JSON.parse(orderable_item_json(menu_item.reload, branch))
    expect(json["groups"].first["name"]).to eq("حار/عادي")
  end
end
