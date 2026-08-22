# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inventory valuation report", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:produce) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let(:dairy) { IngredientCategory.create!(name: "Dairy", position: 2, company: company) }

  def ingredient(name, qty:, cost:, category: produce)
    Ingredient.create!(name: name, ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: cost, quantity_on_hand: qty, company: company)
  end

  def link(ing, supplier, preferred: false)
    SupplierIngredient.create!(supplier: supplier, ingredient: ing, preferred: preferred)
  end

  let(:acme) { Supplier.create!(name: "Acme Foods", company: company) }
  let(:zesty) { Supplier.create!(name: "Zesty Supply", company: company) }

  before { sign_in owner }

  describe "negative on hand" do
    it "values a negative balance at zero rather than as a credit" do
      neg = ingredient("Spoiled Milk", qty: -20, cost: 500, category: dairy)

      expect(neg.stock_value_cents).to eq(0)
    end

    it "keeps a negative balance from pulling down the grand total" do
      ingredient("Tomatoes", qty: 10, cost: 100)   # 1_000
      ingredient("Onions", qty: -50, cost: 100)    # would be -5_000

      get admin_inventory_reports_valuation_path

      expect(response.body).to include(format_money_str(1_000))
      expect(response.body).to include(I18n.t("inventory.reports.valuation.negative_on_hand"))
    end

    it "still values a zero balance at zero" do
      expect(ingredient("Empty", qty: 0, cost: 900).stock_value_cents).to eq(0)
    end

    def format_money_str(cents)
      Money.new(cents).format(locale: I18n.locale, symbol: ApplicationHelper::MONEY_SYMBOL)
    end
  end

  describe "grouping by vendor" do
    it "puts an unsourced ingredient in its own section" do
      ingredient("Orphan Herb", qty: 5, cost: 100)

      get admin_inventory_reports_valuation_path(group_by: "vendor")

      expect(response.body).to include(I18n.t("inventory.reports.valuation.no_vendor"))
      expect(response.body).to include("Orphan Herb")
    end

    it "groups a single-vendor ingredient under that vendor" do
      link(ingredient("Tomatoes", qty: 5, cost: 100), acme)

      get admin_inventory_reports_valuation_path(group_by: "vendor")

      expect(response.body).to include("Acme Foods")
    end

    it "uses the preferred vendor when an ingredient has several" do
      multi = ingredient("Cheese", qty: 5, cost: 100, category: dairy)
      link(multi, acme)
      link(multi, zesty, preferred: true)

      get admin_inventory_reports_valuation_path(group_by: "vendor")

      expect(response.body).not_to include(I18n.t("inventory.reports.valuation.multiple_vendors"))
      expect(response.body).to include("Zesty Supply")
    end

    it "flags an ambiguous ingredient instead of silently picking a vendor" do
      multi = ingredient("Cheese", qty: 5, cost: 100, category: dairy)
      link(multi, acme)
      link(multi, zesty)

      get admin_inventory_reports_valuation_path(group_by: "vendor")

      expect(response.body).to include(I18n.t("inventory.reports.valuation.multiple_vendors"))
      expect(response.body).to include(I18n.t("inventory.reports.valuation.multiple_vendors_hint"))
    end

    it "partitions ingredients so vendor subtotals match the category grand total" do
      link(ingredient("Tomatoes", qty: 10, cost: 100), acme)
      link(ingredient("Milk", qty: 4, cost: 250, category: dairy), zesty)
      ingredient("Orphan Herb", qty: 5, cost: 100)
      multi = ingredient("Cheese", qty: 2, cost: 300, category: dairy)
      link(multi, acme)
      link(multi, zesty)

      get admin_inventory_reports_valuation_path(group_by: "vendor")
      vendor_total = response.body

      get admin_inventory_reports_valuation_path
      category_total = response.body

      # Same grand-total figure rendered under both groupings.
      total = 1_000 + 1_000 + 500 + 600
      money = Money.new(total).format(locale: I18n.locale, symbol: ApplicationHelper::MONEY_SYMBOL)
      expect(vendor_total).to include(money)
      expect(category_total).to include(money)
    end

    it "defaults to the category grouping" do
      get admin_inventory_reports_valuation_path

      expect(response.body).to include(I18n.t("inventory.reports.valuation.stats.categories"))
    end
  end

  describe "unusable unit costs" do
    it "flags an item with no unit cost, in the row and in a banner" do
      ingredient("Unpriced Herb", qty: 12, cost: 0)

      get admin_inventory_reports_valuation_path

      expect(response.body).to include(I18n.t("inventory.reports.valuation.zero_cost"))
      expect(response.body).to include(I18n.t("inventory.reports.valuation.cost_issue_count", count: 1))
      expect(response.body).to include(I18n.t("inventory.reports.valuation.cost_issue_hint"))
    end

    it "flags a negative unit cost distinctly from a missing one" do
      ingredient("Bad Data", qty: 5, cost: -100)

      get admin_inventory_reports_valuation_path

      expect(response.body).to include(I18n.t("inventory.reports.valuation.negative_cost"))
      expect(response.body).not_to include(I18n.t("inventory.reports.valuation.zero_cost"))
    end

    it "counts every affected item and links each one" do
      ingredient("Unpriced A", qty: 1, cost: 0)
      ingredient("Unpriced B", qty: 2, cost: 0, category: dairy)
      ingredient("Priced", qty: 3, cost: 500)

      get admin_inventory_reports_valuation_path

      expect(response.body).to include(I18n.t("inventory.reports.valuation.cost_issue_count", count: 2))
      expect(response.body).to include("Unpriced A", "Unpriced B")
    end

    it "shows no banner when every item has a usable cost" do
      ingredient("Priced", qty: 3, cost: 500)

      get admin_inventory_reports_valuation_path

      expect(response.body).not_to include(I18n.t("inventory.reports.valuation.cost_issue_hint"))
      expect(response.body).not_to include(I18n.t("inventory.reports.valuation.zero_cost"))
    end

    it "flags the rows in the vendor view too" do
      link(ingredient("Unpriced Herb", qty: 12, cost: 0), acme)

      get admin_inventory_reports_valuation_path(group_by: "vendor")

      expect(response.body).to include(I18n.t("inventory.reports.valuation.zero_cost"))
    end
  end

  describe "expand / collapse" do
    before do
      link(ingredient("Tomatoes", qty: 5, cost: 100), acme)
      ingredient("Milk", qty: 4, cost: 250, category: dairy)
    end

    %w[category vendor].each do |grouping|
      it "renders collapsible groups in the #{grouping} view" do
        get admin_inventory_reports_valuation_path(group_by: grouping)

        # Native <details>, so a group still toggles with no JS at all.
        expect(response.body.scan("<details").size).to eq(2)
        expect(response.body).to include('data-details-group-target="section"')
      end

      it "starts expanded in the #{grouping} view so nothing is hidden on arrival" do
        get admin_inventory_reports_valuation_path(group_by: grouping)

        expect(response.body).to include("<details open")
      end

      it "offers bulk controls in the #{grouping} view" do
        get admin_inventory_reports_valuation_path(group_by: grouping)

        expect(response.body).to include('data-action="details-group#expandAll"')
        expect(response.body).to include('data-action="details-group#collapseAll"')
        expect(response.body).to include(I18n.t("inventory.reports.valuation.expand_all"))
        expect(response.body).to include(I18n.t("inventory.reports.valuation.collapse_all"))
      end
    end

    it "keeps each subtotal in the header so a collapsed group still reads" do
      get admin_inventory_reports_valuation_path

      # Header subtotal renders inside <summary>, above the table.
      summaries = response.body.scan(/<summary.*?<\/summary>/m)
      expect(summaries.size).to eq(2)
      expect(summaries.join).to include(Money.new(500).format(locale: I18n.locale, symbol: ApplicationHelper::MONEY_SYMBOL))
    end
  end

  describe "CSV" do
    it "carries a vendor column" do
      link(ingredient("Tomatoes", qty: 5, cost: 100), acme)

      get admin_inventory_reports_valuation_path(format: :csv)

      expect(response.body).to include("Vendor")
      expect(response.body).to include("Acme Foods")
    end
  end
end
