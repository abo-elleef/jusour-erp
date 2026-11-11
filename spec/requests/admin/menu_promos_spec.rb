# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin menu promos", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "renders a searchable menu item picker on the new promo form" do
    category = create(:category, company: company, name: "Burgers")
    create(:menu_item, company: company, category: category, name: "Cheeseburger", code: "BURG-01")

    get new_admin_menu_promo_path

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    form = doc.at("input[name='menu_promo[name]']").ancestors("form").first
    options = JSON.parse(form["data-searchable-select-options"])

    expect(form.at("[data-controller='searchable-select']")).to be_present
    expect(form.at("input[type='hidden'][name='menu_promo[menu_item_id]']")).to be_present
    expect(form.at("select[name='menu_promo[menu_item_id]']")).to be_nil
    expect(options).to include(
      a_hash_including(
        "label" => "Cheeseburger",
        "keywords" => "Burgers BURG-01",
        "aliases" => ["Burgers", "BURG-01"]
      )
    )
  end

  it "saves a promo that applies only to one choice of the item" do
    category = create(:category, company: company)
    item = create(:menu_item, company: company, category: category, name: "Chicken Run", base_price_cents: 12_000)
    group = ModifierGroup.create!(company: company, name: "Size")
    double = group.modifiers.create!(name: "Double", price_adjustment_cents: 2_000)
    item.menu_item_modifier_groups.create!(modifier_group: group, position: 1)

    get new_admin_menu_promo_path
    choices = JSON.parse(Nokogiri::HTML(response.body).at("form[data-controller='promo-modifier']")["data-promo-modifier-choices-value"])
    expect(choices[item.id]).to contain_exactly(a_hash_including("id" => double.id, "label" => a_string_including("Double")))

    post admin_menu_promos_path, params: { menu_promo: {
      name: "Double deal", menu_item_id: item.id, modifier_id: double.id, promo_price_pounds: "130",
      starts_at: 1.hour.ago, ends_at: 1.day.from_now, active: "1", highlight: "1"
    } }

    expect(response).to redirect_to(admin_menu_promos_path)
    expect(MenuPromo.last.modifier).to eq(double)
  end
end
