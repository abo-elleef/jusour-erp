# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Admin::Accounting sales report CSV", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:mains) { create(:category, company: company, name: "سندوتشات بيف") }
  let(:drinks) { create(:category, company: company, name: "Drinks") }
  let(:range) { { start_date: Date.current, end_date: Date.current, locale: :en } }

  before do
    Current.company = company
    sign_in owner
    burger = create(:menu_item, company: company, category: mains, name: "Burger", base_price_cents: 1000)
    cola = create(:menu_item, company: company, category: drinks, name: "Cola", base_price_cents: 300)
    order = create(:order, user: owner, company: company, status: "completed",
                           subtotal_cents: 2300, total_cents: 2800,
                           created_at: Time.zone.now.change(hour: 12))
    # Set after create: the order's own callbacks reset the fee for a pickup.
    order.update_column(:delivery_fee_cents, 500)
    line = create(:order_item, order: order, menu_item: burger, quantity: 2, unit_price_cents: 1000)
    create(:order_item, order: order, menu_item: cola, quantity: 1, unit_price_cents: 300)
    size = ModifierGroup.create!(company: company, name: "Size")
    double = size.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 500)
    line.order_item_modifiers.create!(modifier: double, name: "Double", price_adjustment_cents: 500)
  end

  BOM = "\uFEFF"

  def csv(params = {})
    get admin_accounting_sales_reports_path(range.merge(params).merge(format: :csv))
    expect(response).to have_http_status(:ok)
    response.body.force_encoding("UTF-8")
  end

  # The rows of one section: from its title row to the next blank row (or,
  # with until_title, up to that section title, skipping blank rows).
  def section(body, title, until_title: nil)
    rows = CSV.parse(body.delete_prefix(BOM))
    after = rows[(rows.index([title]) + 1)..]
    return after.take_while(&:any?) unless until_title

    after.take_while { |r| r != [until_title] }.select(&:any?)
  end

  it "starts with a BOM so Excel reads the Arabic names" do
    expect(csv).to start_with(BOM)
  end

  it "writes amounts as plain numbers, with no currency or thousands separator" do
    body = csv
    expect(body).not_to include("ج.م")
    summary = section(body, "Summary")
    expect(summary).to include(["Gross sales", summary.assoc("Gross sales")[1], "0.00", nil])
    expect(summary.assoc("Gross sales")[1]).to match(/\A\d+\.\d{2}\z/)
  end

  it "has the sections the PDF has" do
    body = csv
    ["Sales report", "Summary", "Payment methods", "Sales by category", "Sales by category & item",
     "Modifier choices", "Sales by hour"].each { |title| expect(CSV.parse(body.delete_prefix(BOM))).to include([title]) }
  end

  it "lists every category with totals, in both the grouped and the flat view" do
    %w[grouped flat].each do |view|
      categories = section(csv(view: view), "Sales by category")
      expect(categories.map(&:first)).to eq(["Category", "سندوتشات بيف", "Drinks", "Total"])
      expect(categories.last[1]).to eq("3")
    end
  end

  it "explains collected vs net sales with the delivery fee" do
    # The sum sits below a blank row inside the section: read to the next title.
    payments = section(csv, "Payment methods", until_title: "Sales by category")
    expect(payments.assoc("Delivery fees")).to eq(["Delivery fees", "5.00"])
    expect(payments.map(&:first)).to include("Net sales", "= Total collected", "Other difference")
  end

  it "follows the page's category filter and leaves modifiers out when asked" do
    body = csv(item_category: "Drinks", modifiers: "0")
    items = section(body, "Sales by category & item")
    expect(items.map(&:first)).to eq(%w[Item Cola Total])
    expect(CSV.parse(body.delete_prefix(BOM))).not_to include(["Modifier choices"])
  end
end
