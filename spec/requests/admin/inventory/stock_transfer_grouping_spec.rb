# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stock transfer line grouping", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:branch) { create(:location, company: company) }
  let(:produce) { create(:ingredient_category, company: company, name: "Produce") }
  let(:dairy) { create(:ingredient_category, company: company, name: "Dairy") }

  let(:transfer) do
    create(:stock_transfer, company: company, from_location: kitchen,
      to_location: branch, requested_by: owner)
  end

  before do
    Current.company = company
    sign_in owner

    tomatoes = create(:ingredient, company: company, ingredient_category: produce, name: "Tomatoes")
    milk = create(:ingredient, company: company, ingredient_category: dairy, name: "Milk")
    create(:stock_transfer_line, stock_transfer: transfer, ingredient: tomatoes,
      quantity_requested: 5, position: 0)
    create(:stock_transfer_line, stock_transfer: transfer, ingredient: milk,
      quantity_requested: 3, position: 1)
  end

  # Only the progress summary and the print sheet honour the toggle — the
  # send/receive/shipment tables group unconditionally. So assertions must be
  # scoped to those two sections, or they pass for the wrong reason.
  def progress_section(body)
    body[/<h2[^>]*>\s*#{Regexp.escape(I18n.t("inventory.stock_transfers.line_items"))}.*?<\/section>/m]
  end

  def print_section(body)
    body[/<section class="print-only stock-transfer-print.*?<\/section>/m]
  end

  def category_header_count(fragment)
    fragment.to_s.scan("data-transfer-category-header").size
  end

  describe "the progress summary" do
    it "groups by category by default" do
      get admin_inventory_stock_transfer_path(transfer)

      section = progress_section(response.body)
      expect(section).to be_present
      expect(category_header_count(section)).to eq(2)
      expect(section).to include("Produce", "Dairy")
    end

    it "shows the grouped toggle as the active pill" do
      get admin_inventory_stock_transfer_path(transfer)

      grouped_link = response.body[/<a[^>]*>\s*#{Regexp.escape(I18n.t("inventory.stock_transfers.group_by_category"))}\s*<\/a>/m]
      flat_link = response.body[/<a[^>]*>\s*#{Regexp.escape(I18n.t("inventory.stock_transfers.flat_list"))}\s*<\/a>/m]

      expect(grouped_link).to include("bg-amber-50")
      expect(flat_link).not_to include("bg-amber-50")
      # Grouped is the bare path now; flat is the explicit opt-out.
      expect(flat_link).to include("grouped=0")
    end

    it "drops the headers on an explicit opt-out" do
      get admin_inventory_stock_transfer_path(transfer, grouped: 0)

      expect(category_header_count(progress_section(response.body))).to eq(0)
    end

    it "keeps an old ?grouped=1 bookmark grouped" do
      get admin_inventory_stock_transfer_path(transfer, grouped: 1)

      expect(category_header_count(progress_section(response.body))).to eq(2)
    end
  end

  describe "the print sheet" do
    it "is grouped by default" do
      get admin_inventory_stock_transfer_path(transfer)

      section = print_section(response.body)
      expect(section).to be_present
      expect(section).to include("Produce", "Dairy")
      # Print headers are plain rows, counted by their shaded cell.
      expect(section.scan("bg-gray-200").size).to eq(2)
    end

    it "is flat when the flat list is chosen" do
      get admin_inventory_stock_transfer_path(transfer, grouped: 0)

      section = print_section(response.body)
      expect(section).to be_present
      expect(section.scan("bg-gray-200").size).to eq(0)
    end
  end
end
