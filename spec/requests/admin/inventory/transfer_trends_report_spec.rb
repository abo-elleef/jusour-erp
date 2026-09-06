# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inventory transfer trends report", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:other_branch) { create(:location, company: company, name: "Branch B") }
  let(:category) { create(:ingredient_category, company: company) }

  def ingredient(name, unit: "kg")
    create(:ingredient, company: company, ingredient_category: category, name: name, unit: unit)
  end

  # Builds a completed transfer directly: this report reads stored quantities, so
  # driving the whole send/receive flow would only slow the spec down.
  def completed_transfer(on:, from: kitchen, to: branch, lines: {}, status: "completed")
    transfer = create(:stock_transfer, company: company, from_location: from, to_location: to,
      requested_by: owner, transferred_on: on, status: status)
    lines.each do |ing, (requested, received)|
      create(:stock_transfer_line, stock_transfer: transfer, ingredient: ing,
        quantity_requested: requested, quantity_sent: requested, quantity_received: received)
    end
    transfer
  end

  def trends(**params)
    get admin_inventory_reports_transfer_trends_path(
      { start_date: 30.days.ago.to_date, end_date: Date.current }.merge(params)
    )
    assigns_trends
  end

  def assigns_trends
    controller_trends = @request.env["action_controller.instance"].instance_variable_get(:@trends)
    controller_trends
  end

  def row_for(result, ingredient_name)
    result.rows.find { |row| row.ingredient.name == ingredient_name }
  end

  before { sign_in owner }

  describe "which transfers count" do
    it "counts completed transfers only" do
      tomatoes = ingredient("Tomatoes")
      completed_transfer(on: 3.days.ago.to_date, lines: { tomatoes => [10, 10] })
      completed_transfer(on: 2.days.ago.to_date, lines: { tomatoes => [99, 99] }, status: "awaiting_receipt")
      completed_transfer(on: 2.days.ago.to_date, lines: { tomatoes => [77, 77] }, status: "cancelled")

      result = trends

      expect(result.rows.size).to eq(1)
      expect(row_for(result, "Tomatoes").total).to eq(10)
    end

    it "measures what arrived, not what was requested" do
      tomatoes = ingredient("Tomatoes")
      # Closed short: completed, but only part of the request ever landed.
      completed_transfer(on: 3.days.ago.to_date, lines: { tomatoes => [10, 4] })

      expect(row_for(trends, "Tomatoes").total).to eq(4)
    end

    it "ignores lines that never arrived" do
      tomatoes = ingredient("Tomatoes")
      onions = ingredient("Onions")
      completed_transfer(on: 3.days.ago.to_date, lines: { tomatoes => [10, 10], onions => [5, 0] })

      result = trends

      expect(result.rows.map { |r| r.ingredient.name }).to eq(["Tomatoes"])
    end

    it "excludes transfers outside the date range" do
      tomatoes = ingredient("Tomatoes")
      completed_transfer(on: 3.days.ago.to_date, lines: { tomatoes => [10, 10] })
      completed_transfer(on: 90.days.ago.to_date, lines: { tomatoes => [50, 50] })

      expect(row_for(trends, "Tomatoes").total).to eq(10)
    end
  end

  describe "units" do
    it "reports each item in its own unit and never sums across items" do
      tomatoes = ingredient("Tomatoes", unit: "kg")
      cups = ingredient("Cups", unit: "pieces")
      completed_transfer(on: 3.days.ago.to_date, lines: { tomatoes => [10, 10], cups => [200, 200] })

      result = trends

      expect(row_for(result, "Tomatoes").unit).to eq("kg")
      expect(row_for(result, "Cups").unit).to eq("pieces")
      expect(result.rows.map(&:total)).to contain_exactly(10, 200)
    end

    it "labels every chart series with its unit, since the axis is mixed" do
      ingredient("Tomatoes", unit: "kg")
      completed_transfer(on: 3.days.ago.to_date, lines: { Ingredient.find_by(name: "Tomatoes") => [10, 10] })

      get admin_inventory_reports_transfer_trends_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      expect(response.body).to include("Tomatoes (")
    end
  end

  describe "routes" do
    it "splits the same item on different routes into separate rows" do
      tomatoes = ingredient("Tomatoes")
      completed_transfer(on: 3.days.ago.to_date, to: branch, lines: { tomatoes => [10, 10] })
      completed_transfer(on: 3.days.ago.to_date, to: other_branch, lines: { tomatoes => [4, 4] })

      result = trends

      expect(result.rows.size).to eq(2)
      expect(result.routes.size).to eq(2)
      expect(result.rows.map(&:total)).to contain_exactly(10, 4)
    end

    it "counts a transfer once per route however many items it carried" do
      tomatoes = ingredient("Tomatoes")
      onions = ingredient("Onions")
      completed_transfer(on: 3.days.ago.to_date, lines: { tomatoes => [10, 10], onions => [5, 5] })

      route = trends.routes.first

      expect(route[:ingredient_count]).to eq(2)
      expect(route[:transfer_count]).to eq(1)
    end

    it "filters by origin and destination" do
      tomatoes = ingredient("Tomatoes")
      completed_transfer(on: 3.days.ago.to_date, to: branch, lines: { tomatoes => [10, 10] })
      completed_transfer(on: 3.days.ago.to_date, to: other_branch, lines: { tomatoes => [4, 4] })

      result = trends(to_location_id: other_branch.id)

      expect(result.rows.size).to eq(1)
      expect(result.rows.first.total).to eq(4)
      expect(result.rows.first.to_location).to eq(other_branch)
    end
  end

  describe "periods" do
    it "buckets by day and keeps empty periods so the line reads as a trend" do
      tomatoes = ingredient("Tomatoes")
      completed_transfer(on: Date.current, lines: { tomatoes => [10, 10] })
      completed_transfer(on: 2.days.ago.to_date, lines: { tomatoes => [3, 3] })

      result = trends(start_date: 4.days.ago.to_date, end_date: Date.current, granularity: "day")

      expect(result.granularity).to eq("day")
      expect(result.periods.size).to eq(5)
      row = row_for(result, "Tomatoes")
      expect(row.quantities[Date.current]).to eq(10)
      expect(row.quantities[2.days.ago.to_date]).to eq(3)
      expect(row.quantities[1.day.ago.to_date]).to eq(0)
      # Every period has a point, so the series never joins across a gap.
      expect(result.series.first[:data].size).to eq(5)
    end

    it "rolls several days into one bucket when grouping by month" do
      tomatoes = ingredient("Tomatoes")
      completed_transfer(on: Date.current.beginning_of_month, lines: { tomatoes => [10, 10] })
      completed_transfer(on: Date.current.beginning_of_month + 1, lines: { tomatoes => [5, 5] })

      result = trends(start_date: Date.current.beginning_of_month, end_date: Date.current, granularity: "month")

      row = row_for(result, "Tomatoes")
      expect(row.quantities.size).to eq(1)
      expect(row.quantities[Date.current.beginning_of_month]).to eq(15)
    end

    it "picks a readable bucket when none is asked for" do
      ingredient("Tomatoes")

      expect(trends(start_date: 10.days.ago.to_date, end_date: Date.current).granularity).to eq("day")
      expect(trends(start_date: 120.days.ago.to_date, end_date: Date.current).granularity).to eq("week")
      expect(trends(start_date: 3.years.ago.to_date, end_date: Date.current).granularity).to eq("month")
    end
  end

  describe "the page" do
    it "shows the chart, the toggle list and the data table" do
      tomatoes = ingredient("Tomatoes")
      completed_transfer(on: 3.days.ago.to_date, lines: { tomatoes => [10, 10] })

      get admin_inventory_reports_transfer_trends_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      expect(response.body).to include("chart-series")
      expect(response.body).to include("transfer-trends-chart")
      expect(response.body).to include(I18n.t("inventory.reports.transfer_trends.table_heading"))
      expect(response.body).to include(I18n.t("inventory.reports.transfer_trends.show_all"))
      expect(response.body).to include("Central Kitchen")
    end

    it "says so when nothing completed in the range" do
      ingredient("Tomatoes")

      get admin_inventory_reports_transfer_trends_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      expect(response.body).to include(I18n.t("inventory.reports.transfer_trends.empty"))
    end

    it "is reachable from the reports nav" do
      get admin_inventory_reports_valuation_path

      expect(response.body).to include(admin_inventory_reports_transfer_trends_path)
      expect(response.body).to include(I18n.t("inventory.tools.transfer_trends"))
    end

    it "exports the same rows as CSV" do
      tomatoes = ingredient("Tomatoes", unit: "kg")
      completed_transfer(on: 3.days.ago.to_date, lines: { tomatoes => [10, 7] })

      get admin_inventory_reports_transfer_trends_path(format: :csv, start_date: 30.days.ago.to_date,
        end_date: Date.current, granularity: "month")

      expect(response.body).to include("Ingredient,Unit,From,To,Transfers,Total")
      expect(response.body).to include("Tomatoes,kg,Central Kitchen,Branch A,1,7.0")
    end
    it "starts with only the biggest movers ticked, since 50 lines is unreadable" do
      # Volumes descend with the alphabet so "biggest" and "first" are distinguishable.
      items = 12.times.map { |n| [ingredient("Item #{format('%02d', n)}"), (12 - n) * 10] }
      completed_transfer(on: 3.days.ago.to_date,
        lines: items.to_h { |ing, qty| [ing, [qty, qty]] })

      get admin_inventory_reports_transfer_trends_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      boxes = response.body.scan(/<input[^>]*data-chart-series-target="checkbox"[^>]*>/)
      checked = boxes.map { |box| box.include?("checked") }

      expect(boxes.size).to eq(12)
      expect(checked.count(true)).to eq(8)
      # The ticked ones are the first eight, and the list is ordered by volume.
      expect(checked).to eq([true] * 8 + [false] * 4)
      expect(response.body.index("Item 00")).to be < response.body.index("Item 11")
    end
    it "names the weekday on daily buckets and not on weekly or monthly ones" do
      tomatoes = ingredient("Tomatoes")
      completed_transfer(on: 3.days.ago.to_date, lines: { tomatoes => [10, 10] })
      thursday = Date.new(2026, 8, 13)

      day = trends(start_date: 10.days.ago.to_date, end_date: Date.current, granularity: "day")
      week = trends(start_date: 120.days.ago.to_date, end_date: Date.current, granularity: "week")
      month = trends(start_date: 400.days.ago.to_date, end_date: Date.current, granularity: "month")

      expect(day.period_labels.first).to match(/\A#{I18n.l(day.periods.first, format: "%a")} /)
      expect(week.period_labels.first).to eq(I18n.l(week.periods.first, format: "%d %b"))
      expect(month.period_labels.first).to eq(I18n.l(month.periods.first, format: "%B %Y"))
      expect(thursday.strftime("%a")).to eq("Thu")
    end

    it "puts the chart and the table in one controller scope, keyed by ingredient" do
      tomatoes = ingredient("Tomatoes")
      # Two routes for one item: both rows must follow the same checkbox.
      completed_transfer(on: 3.days.ago.to_date, to: branch, lines: { tomatoes => [10, 10] })
      completed_transfer(on: 3.days.ago.to_date, to: other_branch, lines: { tomatoes => [4, 4] })

      get admin_inventory_reports_transfer_trends_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      expect(response.body).to include('data-chart-series-storage-key-value="saqr:transfer-trends:series"')
      expect(response.body.scan(/data-chart-series-target="tableRow"[^>]*data-ingredient-id="#{tomatoes.id}"/).size).to eq(2)
      expect(response.body).to include(%(data-chart-series-target="checkbox"))
      expect(response.body).to include(%(data-ingredient-id="#{tomatoes.id}"))
      expect(response.body).to include(I18n.t("inventory.reports.transfer_trends.nothing_selected"))
      expect(response.body).to include(I18n.t("inventory.reports.transfer_trends.search_hint"))
    end
  end
end
