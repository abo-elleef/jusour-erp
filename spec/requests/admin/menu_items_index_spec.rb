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

  it "numbers the rows" do
    create(:menu_item, company: company, category: category, name: "Cheeseburger", code: "BURG-01")
    create(:menu_item, company: company, category: category, name: "Cola", code: "DRINK-01")

    get admin_menu_items_path

    row_numbers = Nokogiri::HTML(response.body).css("tbody tr").map { |row| row.css("td").first.text.strip }
    expect(row_numbers).to eq(%w[1 2])
  end

  describe "sorting by a column header" do
    let!(:cola) { create(:menu_item, company: company, category: category, name: "Cola", code: "C-1", base_price_cents: 2_000) }
    let!(:burger) { create(:menu_item, company: company, category: category, name: "burger", code: "B-1", base_price_cents: 9_000) }
    let!(:apple) { create(:menu_item, company: company, category: category, name: "Apple pie", code: "A-1", base_price_cents: 5_000) }

    def names_in_order
      Nokogiri::HTML(response.body).css("tbody tr").map { |row| row.css("td")[3].text.strip }
    end

    it "sorts by name, ignoring case, both ways" do
      get admin_menu_items_path(sort: "name", dir: "asc")
      expect(names_in_order).to eq(["Apple pie", "burger", "Cola"])

      get admin_menu_items_path(sort: "name", dir: "desc")
      expect(names_in_order).to eq(["Cola", "burger", "Apple pie"])
    end

    it "sorts by price and keeps the search filter" do
      get admin_menu_items_path(sort: "price", dir: "desc")
      expect(names_in_order).to eq(["burger", "Apple pie", "Cola"])

      get admin_menu_items_path(sort: "price", dir: "asc", search: "o")
      expect(names_in_order).to eq(["Cola"])
    end

    it "links each header to the opposite direction once active, keeping filters" do
      get admin_menu_items_path(sort: "price", dir: "asc", search: "o")
      link = Nokogiri::HTML(response.body).css("thead a").find { |a| a["href"].include?("sort=price") }
      expect(link["href"]).to include("dir=desc")
      expect(link["href"]).to include("search=o")
    end

    it "ignores an unknown sort key" do
      get admin_menu_items_path(sort: "drop table", dir: "asc")
      expect(response).to have_http_status(:ok)
    end
  end

  it "finds an item by name too" do
    create(:menu_item, company: company, category: category, name: "Falafel Wrap", code: "MI-9001")

    get admin_menu_items_path(search: "falafel")
    expect(response.body).to include("Falafel Wrap")
  end
end
