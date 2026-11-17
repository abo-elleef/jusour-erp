# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting order notes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:mains) { create(:category, company: company, name: "Mains") }
  let(:drinks) { create(:category, company: company, name: "Drinks") }
  let!(:burger) { create(:menu_item, company: company, category: mains, name: "Burger", base_price_cents: 1000) }
  let!(:cola) { create(:menu_item, company: company, category: drinks, name: "Cola", base_price_cents: 300) }
  let(:range) { { start_date: Date.current, end_date: Date.current } }

  before do
    Current.company = company
    sign_in owner
    order = create(:order, user: owner, company: company, status: "completed", notes: "Customer is allergic",
                           subtotal_cents: 1300, total_cents: 1300, created_at: Time.zone.now.change(hour: 12))
    create(:order_item, order: order, menu_item: burger, quantity: 1, unit_price_cents: 1000, notes: "بدون بصل")
    create(:order_item, order: order, menu_item: cola, quantity: 1, unit_price_cents: 300)
  end

  it "lists both kinds of note with a link to the order" do
    get admin_accounting_order_notes_path(range)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Customer is allergic", "بدون بصل", I18n.t("accounting.order_notes.whole_order", locale: :ar))
    expect(response.body).to include(admin_order_path(Order.last))
  end

  it "filters by item" do
    get admin_accounting_order_notes_path(range.merge(item: "m:#{cola.id}"))
    expect(response.body).to include("Customer is allergic")
    expect(response.body).not_to include("بدون بصل")
  end

  it "ignores an item that was not sold in the range" do
    get admin_accounting_order_notes_path(range.merge(item: "m:#{SecureRandom.uuid}"))
    expect(response.body).to include("Customer is allergic", "بدون بصل")
  end

  it "exports the list as CSV" do
    get admin_accounting_order_notes_path(range.merge(format: :csv))
    expect(response.body).to include("Customer is allergic", "بدون بصل", "Burger")
  end

  it "links each Sales report row that has notes to this page, filtered to it" do
    get admin_accounting_sales_reports_path(range)
    section = response.body[/id="items-sold".*?<\/section>/m]
    links = section.scan(/href="([^"]*order_notes[^"]*)"/).flatten.map { |h| CGI.unescapeHTML(h) }
    expect(links).to include(a_string_including("category=#{mains.id}"), a_string_including("item=m%3A#{burger.id}"))
    expect(response.body).to include(I18n.t("accounting.sales_reports.notes_link", locale: :ar))
  end
end
