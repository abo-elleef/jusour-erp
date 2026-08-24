# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Daily production sheet — include all templates", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, :central_kitchen, company: company) }
  let(:category) { IngredientCategory.create!(name: "Prep", position: 1, company: company) }

  def ingredient(name)
    Ingredient.create!(name: name, ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 100, quantity_on_hand: 50, company: company)
  end

  def template(name, output, position: 0)
    t = ManufacturingTemplate.create!(company: company, name: name, yield_quantity: 2,
      output_ingredient: output, position: position, active: false)
    t.manufacturing_template_lines.create!(ingredient: ingredient("#{name} input"),
      quantity_used: 1, unit: "kg")
    t.update!(active: true)
    t
  end

  let!(:made) { ingredient("Made Today") }
  let!(:idle) { ingredient("Never Made") }
  # "Zebra output" sits at position 1 and "Apple output" at 3, so template order and
  # alphabetical order disagree — otherwise an ordering test proves nothing.
  let!(:zebra) { ingredient("Zebra output") }
  let!(:apple) { ingredient("Apple output") }
  let!(:made_template) { template("Makes something", made, position: 5) }
  let!(:idle_template) { template("Makes nothing", idle, position: 6) }
  let!(:zebra_template) { template("Zebra tmpl", zebra, position: 1) }
  let!(:apple_template) { template("Apple tmpl", apple, position: 3) }

  before do
    sign_in owner
    ::Inventory::RunManufacturingService.new(
      template: made_template, user: owner, location: location,
      runs_count: 3, occurred_on: Date.current, shelf_life_days: 2
    ).call
  end

  def daily(params = {})
    get admin_inventory_manufacturing_runs_path({ view: "daily", date: Date.current }.merge(params))
    response.body
  end

  it "shows only what was produced by default" do
    body = daily

    expect(body).to include("Made Today")
    expect(body).not_to include("Never Made")
  end

  it "includes idle templates when asked" do
    body = daily(include_all: 1)

    expect(body).to include("Made Today")
    expect(body).to include("Never Made")
  end

  it "shows zero for a template that produced nothing" do
    body = daily(include_all: 1)
    row = body[/Never Made.*?<\/tr>/m]

    expect(row).to be_present
    expect(row).to match(/>\s*0\s*</)
  end

  it "keeps the real produced quantity alongside the zeros" do
    body = daily(include_all: 1)
    row = body[/Made Today.*?<\/tr>/m]

    # 3 runs x yield 2 = 6
    expect(row).to match(/>\s*6\s*</)
  end

  it "offers the toggle in the UI" do
    body = daily

    expect(body).to include(I18n.t("inventory.manufacturing.runs.include_all_templates"))
    expect(body).to include('name="include_all"')
  end

  it "keeps the toggle checked after applying it" do
    body = daily(include_all: 1)

    expect(body).to match(/name="include_all"[^>]*value="1"[^>]*checked/)
      .or match(/checked[^>]*name="include_all"[^>]*value="1"/)
  end

  it "numbers the rows from 1 for the UI" do
    body = daily(include_all: 1)
    header_and_rows = body[/<thead.*?<\/tbody>/m]

    expect(header_and_rows).to include(I18n.t("shared.row_index"))
    # Two rows: produced and idle, numbered 1 and 2.
    expect(header_and_rows.scan(/tabular-nums">\s*(\d+)\s*</).flatten.first(2)).to eq(%w[1 2])
  end

  it "orders rows by template position, not alphabetically" do
    body = daily(include_all: 1)
    order = %w[Zebra\ output Apple\ output].map { |n| body.index(n.tr("\\", "")) }

    expect(order.compact.size).to eq(2)
    expect(order[0]).to be < order[1]
  end

  it "keeps the page chrome off the printed sheet" do
    body = daily(include_all: 1)

    # Title and view tabs are hidden in print; only the daily card prints.
    expect(body).to match(/class="[^"]*print:hidden[^"]*"[^>]*>\s*<div>\s*<h1/)
    expect(body).to include("print:hidden")
  end

  it "affects the printed sheet, which is the same table" do
    body = daily(include_all: 1)

    # No separate print view — the print button prints this table.
    expect(body).to include('onclick="window.print()"')
    expect(body).to include("Never Made")
  end

  describe "a day with no production at all" do
    it "still lists every template when asked" do
      body = daily(date: Date.current - 5, include_all: 1)

      expect(body).to include("Made Today", "Never Made")
      expect(body).not_to include(
        I18n.t("inventory.manufacturing.runs.daily_empty", date: I18n.l(Date.current - 5, format: :long))
      )
    end

    it "says nothing was produced when not asked" do
      body = daily(date: Date.current - 5)

      expect(body).to include(
        I18n.t("inventory.manufacturing.runs.daily_empty", date: I18n.l(Date.current - 5, format: :long))
      )
    end
  end
end
