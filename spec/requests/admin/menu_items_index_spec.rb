# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::MenuItems index code + search", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:category, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "shows the code column and finds an item by its code" do
    burger = create(:menu_item, company: company, category: category, name: "Cheeseburger", code: "BURG-01")
    create(:menu_item, company: company, category: category, name: "Cola", code: "DRINK-01")

    get admin_menu_items_path
    expect(response.body).to include("BURG-01")

    get admin_menu_items_path(search: "burg-01")
    expect(response.body).to include("Cheeseburger")
    expect(response.body).not_to include("Cola")
  end

  it "finds an item by name too" do
    create(:menu_item, company: company, category: category, name: "Falafel Wrap", code: "MI-9001")

    get admin_menu_items_path(search: "falafel")
    expect(response.body).to include("Falafel Wrap")
  end
end
