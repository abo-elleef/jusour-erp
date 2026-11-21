# frozen_string_literal: true

require "rails_helper"

# Distribution sidebar: Sales holds only the selling work, the public website is
# its own module, set-once sales setup sits in Settings and Tickets is a link of
# its own next to Customers.
RSpec.describe "Admin sidebar: Sales, Website, Settings grouping", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }

  before do
    Current.company = company
    sign_in owner
  end

  # The links inside one module's panel in the sidebar.
  def module_links(key)
    panel = Nokogiri::HTML(response.body)
      .at_css(%(nav [data-nested-nav-key-value="#{key}"] [data-nested-nav-target="modulePanel"]))
    panel ? panel.css("a").map { |a| a["href"] } : []
  end

  def module_open?(key)
    Nokogiri::HTML(response.body)
      .at_css(%(nav [data-nested-nav-key-value="#{key}"]))&.[]("data-nested-nav-open-value") == "true"
  end

  it "lists only the selling work under Sales, in funnel order" do
    get admin_sales_customer_invoices_path

    expect(module_links("sales")).to eq([
      admin_sales_leads_path,
      admin_sales_customer_invoices_path,
      admin_sales_customer_invoices_path(status: "pending_payment_confirmation"),
      admin_sales_credit_notes_path,
      admin_sales_customer_statements_path,
      admin_sales_shipping_companies_path
    ])
    expect(module_open?("sales")).to be(true)
  end

  it "gives the public website its own module" do
    get admin_sales_storefront_listings_path

    expect(module_links("website")).to eq([
      admin_sales_storefront_listings_path,
      admin_sales_storefront_categories_path,
      admin_sales_storefront_sections_path,
      admin_sales_storefront_pages_path,
      admin_sales_storefront_path
    ])
    expect(module_open?("website")).to be(true)
    expect(module_open?("sales")).to be(false)
  end

  it "puts price tiers, payment methods and invoice stages in Settings under a Sales heading" do
    get admin_sales_price_tiers_path

    settings = module_links("settings")
    expect(settings).to include(admin_sales_price_tiers_path, admin_sales_payment_methods_path, admin_sales_stage_access_path)
    expect(module_links("sales")).not_to include(admin_sales_price_tiers_path)
    expect(module_open?("settings")).to be(true)
    expect(module_open?("sales")).to be(false)

    panel = Nokogiri::HTML(response.body)
      .at_css(%(nav [data-nested-nav-key-value="settings"] [data-nested-nav-target="modulePanel"]))
    expect(panel.css("span").map(&:text).map(&:strip)).to include(I18n.t("nav.sales"))
  end

  it "keeps invoice stages owner-only" do
    manager = create(:user, :manager, company: company, wages_account_code: 2502)
    sign_in manager
    get admin_root_path

    expect(response.body).not_to include(admin_sales_stage_access_path)
  end

  it "shows Tickets as its own link, outside Sales" do
    get admin_sales_tickets_path

    expect(module_links("sales")).not_to include(admin_sales_tickets_path)
    expect(Nokogiri::HTML(response.body).css("nav > a").map { |a| a["href"] }).to include(admin_sales_tickets_path)
    expect(module_open?("sales")).to be(false)
  end

  it "has no Website module for a restaurant" do
    restaurant = create(:company, business_type: "restaurant")
    Current.company = restaurant
    sign_in create(:user, :owner, company: restaurant, wages_account_code: 2503)
    get admin_root_path

    expect(module_links("website")).to be_empty
  end
end
