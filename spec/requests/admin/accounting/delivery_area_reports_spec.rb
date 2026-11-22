# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting delivery area report", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let!(:zamalek) { DeliveryArea.create!(company: company, location: branch, name: "Zamalek", fee_cents: 3_000) }
  let!(:maadi) { DeliveryArea.create!(company: company, location: branch, name: "Maadi", fee_cents: 4_000) }
  let!(:quiet) { DeliveryArea.create!(company: company, location: branch, name: "Quiet zone", fee_cents: 2_000) }
  let(:range) { { start_date: Date.current, end_date: Date.current } }

  before do
    Current.company = company
    sign_in owner
  end

  def delivery(area:, fee:, food:, status: "completed", discount: 0, type: "delivery")
    create(:order, user: owner, company: company, location: branch, status: status, order_type: type,
                   delivery_area: area, delivery_fee_cents: fee, subtotal_cents: food, discount_cents: discount,
                   total_cents: food - discount + fee, created_at: Time.zone.now.change(hour: 12))
  end

  def rows
    Nokogiri::HTML(response.body).css("[data-testid=delivery-area-row]").map { |tr| tr.css("td").map { |td| td.text.squish } }
  end

  def totals
    Nokogiri::HTML(response.body).at("[data-testid=delivery-area-totals]").css("td").map { |td| td.text.squish }
  end

  it "counts orders, fees charged and food per area, with a No area row and quiet areas at zero" do
    delivery(area: zamalek, fee: 3_000, food: 10_000)
    delivery(area: zamalek, fee: 3_500, food: 20_000, discount: 2_000) # cashier changed the fee
    delivery(area: maadi, fee: 4_000, food: 15_000)
    delivery(area: nil, fee: 2_500, food: 5_000)

    get admin_accounting_delivery_area_reports_path(range)

    expect(response).to have_http_status(:ok)
    names = rows.map(&:first)
    expect(names.first(3)).to eq(["Zamalek", "Maadi", "Quiet zone"]) # most orders first
    expect(names.last).to start_with(I18n.t("accounting.delivery_area_reports.no_area", locale: :ar))

    zam = rows.first
    expect(zam[1]).to eq("2")        # orders
    expect(zam[2]).to eq("50.0%")    # 2 of 4 delivery orders
    expect(zam[3]).to include("65")  # fees charged: 30 + 35
    expect(zam[5]).to include("280") # food after discount: 100 + 180

    expect(rows[2][1]).to eq("0") # Quiet zone listed with zero
    expect(totals[1]).to eq("4")
    expect(totals[3]).to include("130")
  end

  it "leaves out cancelled (voided), draft and non-delivery orders" do
    delivery(area: zamalek, fee: 3_000, food: 10_000)
    delivery(area: zamalek, fee: 3_000, food: 10_000, status: "cancelled")
    delivery(area: zamalek, fee: 3_000, food: 10_000, status: "draft")
    delivery(area: nil, fee: 0, food: 10_000, type: "pickup")

    get admin_accounting_delivery_area_reports_path(range)

    expect(rows.first.first(2)).to eq(["Zamalek", "1"])
    expect(totals[1]).to eq("1")
    expect(rows.map(&:first)).not_to include(a_string_starting_with(I18n.t("accounting.delivery_area_reports.no_area", locale: :ar)))
  end

  it "keeps a switched-off area that still has orders in range, and hides switched-off ones without" do
    delivery(area: maadi, fee: 4_000, food: 15_000)
    maadi.update!(active: false)
    quiet.update!(active: false)

    get admin_accounting_delivery_area_reports_path(range)

    names = rows.map(&:first)
    expect(names).to include(a_string_starting_with("Maadi"))
    expect(names).not_to include("Quiet zone")
  end

  it "filters by branch" do
    other = create(:location, company: company, name: "Other Branch")
    remote = DeliveryArea.create!(company: company, location: other, name: "Remote", fee_cents: 9_000)
    create(:order, user: owner, company: company, location: other, status: "completed", order_type: "delivery",
                   delivery_area: remote, delivery_fee_cents: 9_000, subtotal_cents: 1_000, total_cents: 10_000,
                   created_at: Time.zone.now.change(hour: 12))
    delivery(area: zamalek, fee: 3_000, food: 10_000)

    get admin_accounting_delivery_area_reports_path(range.merge(location_id: branch.id))
    expect(rows.map(&:first)).not_to include("Remote")
    expect(totals[1]).to eq("1")

    get admin_accounting_delivery_area_reports_path(range)
    expect(rows.map(&:first)).to include("Remote")
  end

  it "sorts by a column, keeping No area last" do
    delivery(area: zamalek, fee: 3_000, food: 10_000)
    delivery(area: maadi, fee: 4_000, food: 15_000)
    delivery(area: nil, fee: 9_900, food: 5_000)

    get admin_accounting_delivery_area_reports_path(range.merge(sort: "fees", dir: "desc"))
    expect(rows.map(&:first).first(2)).to eq(["Maadi", "Zamalek"])
    expect(rows.last.first).to start_with(I18n.t("accounting.delivery_area_reports.no_area", locale: :ar))

    get admin_accounting_delivery_area_reports_path(range.merge(sort: "name", dir: "asc"))
    expect(rows.map(&:first).first(3)).to eq(["Maadi", "Quiet zone", "Zamalek"])
  end

  it "links each area to its settings page" do
    delivery(area: zamalek, fee: 3_000, food: 10_000)
    get admin_accounting_delivery_area_reports_path(range)
    expect(response.body).to include(edit_admin_location_delivery_area_path(branch, zamalek))
  end

  it "exports the rows as CSV" do
    delivery(area: zamalek, fee: 3_000, food: 10_000)
    get admin_accounting_delivery_area_reports_path(range.merge(format: :csv))
    expect(response.body).to include("Zamalek", "30.00", "100.00")
  end

  it "is listed in the Reports hub" do
    get admin_reports_path
    expect(response.body).to include(admin_accounting_delivery_area_reports_path)
  end

  it "is refused to a user without accounting reports permission" do
    sign_in create(:user, company: company, role: "cashier")
    get admin_accounting_delivery_area_reports_path(range)
    expect(response).not_to have_http_status(:ok)
  end

  describe "the top areas chart" do
    def chart_data
      el = Nokogiri::HTML(response.body).at("#delivery-area-bar-chart")
      el && JSON.parse(el["data-chartkick-bar-data-value"])
    end

    it "shows the top areas by orders, lumps the rest, and puts No area last" do
      areas = (1..12).map { |i| DeliveryArea.create!(company: company, location: branch, name: "Area #{format('%02d', i)}", fee_cents: 1_000) }
      areas.each_with_index { |a, i| (12 - i).times { delivery(area: a, fee: 1_000, food: 5_000) } } # Area 01 has 12 … Area 12 has 1
      2.times { delivery(area: nil, fee: 500, food: 5_000) }

      get admin_accounting_delivery_area_reports_path(range)

      labels = chart_data.map(&:first)
      expect(labels.first(10)).to eq((1..10).map { |i| "Area #{format('%02d', i)}" })
      expect(labels[10]).to include("(2)")              # Area 11 + Area 12
      expect(chart_data[10].last).to eq(3)               # 2 + 1 orders
      expect(chart_data.last).to eq([I18n.t("accounting.delivery_area_reports.no_area", locale: :ar), 2])
      expect(labels).not_to include("Quiet zone")         # areas with no orders stay out
    end

    it "switches to delivery fees" do
      delivery(area: zamalek, fee: 3_000, food: 10_000)
      delivery(area: zamalek, fee: 3_000, food: 10_000)
      delivery(area: maadi, fee: 9_000, food: 10_000)

      get admin_accounting_delivery_area_reports_path(range.merge(chart: "fees"))

      expect(chart_data).to eq([["Maadi", 90.0], ["Zamalek", 60.0]])
      expect(Nokogiri::HTML(response.body).at("#delivery-area-chart a[aria-selected=true]").text).to eq(
        I18n.t("accounting.delivery_area_reports.chart_metrics.fees", locale: :ar)
      )
    end

    it "adds the branch to a label only when the bars mix branches" do
      other = create(:location, company: company, name: "Other Branch")
      remote = DeliveryArea.create!(company: company, location: other, name: "Remote", fee_cents: 9_000)
      create(:order, user: owner, company: company, location: other, status: "completed", order_type: "delivery",
                     delivery_area: remote, delivery_fee_cents: 9_000, subtotal_cents: 1_000, total_cents: 10_000,
                   created_at: Time.zone.now.change(hour: 12))
      delivery(area: zamalek, fee: 3_000, food: 10_000)

      get admin_accounting_delivery_area_reports_path(range)
      expect(chart_data.map(&:first)).to contain_exactly("Zamalek · Main Branch", "Remote · Other Branch")

      get admin_accounting_delivery_area_reports_path(range.merge(location_id: branch.id))
      expect(chart_data.map(&:first)).to eq(["Zamalek"])
    end

    it "is not drawn when there are no delivery orders" do
      get admin_accounting_delivery_area_reports_path(range)
      expect(chart_data).to be_nil
    end
  end
  describe "links to the orders behind each number" do
    def link_hrefs(selector)
      Nokogiri::HTML(response.body).css("#{selector} a[href^='/admin/orders']").map { |a| a["href"] }
    end

    it "opens an orders list that adds up to the clicked row and total" do
      delivery(area: zamalek, fee: 3_000, food: 10_000)
      delivery(area: zamalek, fee: 3_500, food: 20_000, discount: 2_000)
      delivery(area: maadi, fee: 4_000, food: 15_000)
      delivery(area: nil, fee: 2_500, food: 5_000)
      delivery(area: nil, fee: 0, food: 9_000, type: "pickup")
      delivery(area: zamalek, fee: 3_000, food: 9_000, status: "submitted") # open: left out by default

      get admin_accounting_delivery_area_reports_path(range)
      zamalek_href = link_hrefs("[data-testid=delivery-area-row]").first
      no_area_href = link_hrefs("[data-testid=delivery-area-row]").last
      total_href = link_hrefs("[data-testid=delivery-area-totals]").first

      get zamalek_href
      expect(response).to have_http_status(:ok)
      summary = Nokogiri::HTML(response.body).at("[data-testid=orders-delivery-summary]").text.squish
      expect(summary).to include("2").and include("65").and include("280")
      expect(response.body).to include(I18n.t("admin.orders.report_filters.area", name: "Zamalek", locale: :ar))

      get no_area_href
      expect(Nokogiri::HTML(response.body).at("[data-testid=orders-delivery-summary]").text.squish).to include("25")

      get total_href
      summary = Nokogiri::HTML(response.body).at("[data-testid=orders-delivery-summary]").text.squish
      expect(summary).to include("4").and include("130")
    end

    it "carries the include-open switch into the orders list" do
      delivery(area: zamalek, fee: 3_000, food: 10_000, status: "submitted")

      get admin_accounting_delivery_area_reports_path(range.merge(include_open: "1"))
      get link_hrefs("[data-testid=delivery-area-row]").first

      expect(Nokogiri::HTML(response.body).at("[data-testid=orders-delivery-summary]").text.squish).to include("30")
    end
  end
end
