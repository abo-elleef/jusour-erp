# frozen_string_literal: true

require "rails_helper"

# Admin picks where a category shows: POS and public menu (default), POS only,
# or public menu only.
RSpec.describe "Category menu visibility", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:category, company: company, name: "Staff meals") }

  before { sign_in owner }

  it "shows the choice on the form, saves it and badges it on the list" do
    get edit_admin_category_path(category)
    expect(response.body).to include('name="category[menu_visibility]"')

    patch admin_category_path(category), params: { category: { menu_visibility: "pos" } }
    expect(category.reload.menu_visibility).to eq("pos")

    get admin_categories_path
    expect(response.body).to include(I18n.t("admin.categories.menu_visibility_pos"))
  end

  it "refuses an unknown value" do
    category.menu_visibility = "kiosk"
    expect(category).not_to be_valid
  end
end
