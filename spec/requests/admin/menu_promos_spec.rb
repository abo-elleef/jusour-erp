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
end
