# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::Reports#movements", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:location) { create(:location, company: company) }
  let(:other_location) { create(:location, company: company) }
  let(:flour) { create(:ingredient, company: company, ingredient_category: category, name: "Report Flour") }
  let(:sugar) { create(:ingredient, company: company, ingredient_category: category, name: "Report Sugar") }

  def adjust(ingredient, delta, type: "manual_add", at: Time.current, loc: location)
    adjustment = StockAdjustment.new(
      ingredient: ingredient, user: owner, location: loc,
      quantity_delta: delta, adjustment_type: type
    )
    adjustment.save!
    adjustment.update_columns(created_at: at, updated_at: at)
    adjustment
  end

  before do
    Current.company = company
    sign_in owner
  end

  # The filter's item picker lists every ingredient by name, so a name alone
  # proves nothing about the rows. The link to the ingredient only appears in a
  # rendered row.
  def listed?(ingredient)
    response.body.include?(admin_inventory_ingredient_path(ingredient))
  end

  it "lists movements for every item, not just one" do
    adjust(flour, 5)
    adjust(sugar, -2, type: "waste_spoilage")

    get admin_inventory_reports_movements_path

    expect(listed?(flour)).to be true
    expect(listed?(sugar)).to be true
  end

  it "defaults to the current month" do
    adjust(flour, 5, at: Date.current.beginning_of_month + 1.hour)
    adjust(sugar, 3, at: Date.current.beginning_of_month - 5.days)

    get admin_inventory_reports_movements_path

    expect(listed?(flour)).to be true
    expect(listed?(sugar)).to be false
  end

  it "filters by item" do
    adjust(flour, 5)
    adjust(sugar, 3)

    get admin_inventory_reports_movements_path(ingredient_id: flour.id)

    expect(listed?(flour)).to be true
    expect(listed?(sugar)).to be false
  end

  it "filters by date range" do
    adjust(flour, 5, at: 2.days.ago)
    adjust(sugar, 3, at: 20.days.ago)

    get admin_inventory_reports_movements_path(
      start_date: 5.days.ago.to_date, end_date: Date.current
    )

    expect(listed?(flour)).to be true
    expect(listed?(sugar)).to be false
  end

  it "filters by location and by adjustment type" do
    adjust(flour, 5, loc: location)
    adjust(sugar, -2, type: "waste_spoilage", loc: other_location)

    get admin_inventory_reports_movements_path(location_id: location.id)
    expect(listed?(flour)).to be true
    expect(listed?(sugar)).to be false

    get admin_inventory_reports_movements_path(adjustment_type: "waste_spoilage")
    expect(listed?(sugar)).to be true
    expect(listed?(flour)).to be false
  end

  it "rolls up net movement per item when grouped" do
    adjust(flour, 5)
    adjust(flour, -2, type: "manual_remove")

    get admin_inventory_reports_movements_path(group: "ingredient")

    expect(listed?(flour)).to be true
    expect(response.body).to include("+3")
  end

  it "never reads another company's movements" do
    other_company = create(:company)
    other_ingredient = nil
    Current.company = other_company
    other_category = create(:ingredient_category, company: other_company)
    other_ingredient = create(:ingredient, company: other_company,
      ingredient_category: other_category, name: "Foreign Item")
    other_user = create(:user, :owner, company: other_company)
    StockAdjustment.create!(ingredient: other_ingredient, user: other_user,
      quantity_delta: 9, adjustment_type: "manual_add")
    Current.company = company

    adjust(flour, 5)
    get admin_inventory_reports_movements_path

    expect(listed?(flour)).to be true
    expect(listed?(other_ingredient)).to be false
    expect(response.body).not_to include("Foreign Item")
  end

  it "exports CSV with the item on every row" do
    adjust(flour, 5)

    get admin_inventory_reports_movements_path(format: :csv)

    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Report Flour")
    expect(response.body).to include("Time,Item,Code")
  end
end
