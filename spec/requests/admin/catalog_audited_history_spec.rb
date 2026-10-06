# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog audited change history", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }

  before { sign_in owner }

  describe "ExpenseCategory" do
    it "records audits and shows history on edit" do
      category = ExpenseCategory.create!(
        name: "Office Supplies", category_type: "other", position: 20, company: company
      )
      expect(category.audits.where(action: "create")).to exist
      expect(category.audits.find_by!(action: "create").associated).to eq(company)

      category.update!(name: "Office Supplies Plus")
      expect(category.audits.where(action: "update")).to exist

      get edit_admin_accounting_expense_category_path(category)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
      expect(response.body).to include("Office Supplies Plus")
    end
  end

  describe "IncomeCategory" do
    it "records audits and shows history on edit" do
      category = IncomeCategory.create!(
        name: "Events", category_type: "catering", position: 20, company: company
      )
      expect(category.audits.where(action: "create")).to exist

      category.update!(name: "Private Events")
      get edit_admin_accounting_income_category_path(category)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
      expect(response.body).to include("Private Events")
    end
  end

  describe "Category (menu item category)" do
    it "records audits and shows history on edit" do
      category = create(:category, company: company, name: "Burgers")
      expect(category.audits.where(action: "create")).to exist

      category.update!(name: "Gourmet Burgers")
      get edit_admin_category_path(category)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
      expect(response.body).to include("Gourmet Burgers")
    end
  end

  describe "IngredientCategory" do
    it "records audits and shows history on edit" do
      category = create(:ingredient_category, company: company, name: "Produce")
      expect(category.audits.where(action: "create")).to exist

      category.update!(name: "Fresh Produce")
      get edit_admin_inventory_ingredient_category_path(category)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
      expect(response.body).to include("Fresh Produce")
    end
  end

  describe "MenuItem" do
    it "records audits and shows history on edit" do
      item = create(:menu_item, company: company, name: "Classic Burger", base_price_cents: 5_000)
      expect(item.audits.where(action: "create")).to exist
      expect(item.audits.find_by!(action: "create").associated).to eq(company)

      item.update!(name: "Classic Burger Deluxe", base_price_cents: 6_500)
      update_audit = item.audits.find_by!(action: "update")
      expect(update_audit.audited_changes.keys).to include("name", "base_price_cents")

      get edit_admin_menu_item_path(item)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
      expect(response.body).to include("Classic Burger Deluxe")
      expect(response.body).to include(I18n.t("accounting.audit_history.fields.base_price_cents"))
    end
  end

  describe "Ingredient" do
    it "records audits (excluding quantity_on_hand) and shows history on show" do
      ingredient = create(:ingredient, company: company, name: "Chicken Breast", quantity_on_hand: 10.0)
      expect(ingredient.audits.where(action: "create")).to exist
      create_changes = ingredient.audits.find_by!(action: "create").audited_changes
      expect(create_changes.keys).not_to include("quantity_on_hand")

      ingredient.update!(name: "Chicken Thigh", quantity_on_hand: 25.0)
      update_audit = ingredient.audits.find_by!(action: "update")
      expect(update_audit.audited_changes.keys).to include("name")
      expect(update_audit.audited_changes.keys).not_to include("quantity_on_hand")

      get admin_inventory_ingredient_path(ingredient)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
      expect(response.body).to include("Chicken Thigh")
    end
  end

  describe "IngredientLocation" do
    it "merges per-location stock audits into the ingredient's own history" do
      ingredient = create(:ingredient, company: company, name: "Water")
      location = create(:location, company: company, name: "Central Warehouse")
      il = create(:ingredient_location, ingredient: ingredient, location: location, quantity_on_hand: 87.0)
      expect(il.audits.where(action: "create")).to exist

      il.update!(quantity_on_hand: 83.0)
      update_audit = il.audits.find_by!(action: "update")
      expect(update_audit.audited_changes.keys).to include("quantity_on_hand")
      expect(update_audit.audited_changes.keys).not_to include("ingredient_id")
      expect(update_audit.associated).to eq(ingredient)

      get admin_inventory_ingredient_path(ingredient)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
      expect(response.body).to include(I18n.t("accounting.audit_history.fields.quantity_on_hand"))
      expect(response.body).to include("Central Warehouse")
    end
  end
end
