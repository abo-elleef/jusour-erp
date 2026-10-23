# frozen_string_literal: true

require "rails_helper"

# Writing to the inventory catalog — ingredients, vendors, categories, units —
# sits behind inventory:settings rather than inventory:manage, so a role can run
# stock day to day without being able to reshape what the stock is made of.
# Reading those screens still only needs inventory:view.
RSpec.describe "Who can edit inventory setup", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }

  # Ahead of the let! records below: they need the tenant set to resolve units.
  before { Current.company = company }

  let(:manager) { create(:user, :manager, company: company) }
  let!(:category) { IngredientCategory.create!(name: "Oils", position: 1, company: company) }
  let!(:ingredient) do
    Ingredient.create!(name: "Ghee", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 0, quantity_on_hand: 0, company: company)
  end
  let!(:supplier) { Supplier.create!(name: "Nile Foods", company: company) }

  # Strip the key the way an owner would from the role editor.
  def revoke_settings!
    role = Role.unscoped.find_by(company_id: company.id, key: "manager")
    role.update!(permissions: role.permission_keys - ["inventory:settings"])
  end

  context "a manager who still holds it" do
    before { sign_in manager }

    it "creates a unit" do
      expect { post admin_inventory_units_path, params: { unit: { name: "20kg sack" } } }
        .to change(company.units, :count).by(1)
    end

    it "renames a vendor" do
      patch admin_inventory_supplier_path(supplier), params: { supplier: { name: "Nile Foods Co" } }
      expect(supplier.reload.name).to eq("Nile Foods Co")
    end

    it "offers the add / edit controls on the setup screens" do
      get admin_inventory_units_path
      expect(response.body).to include(edit_admin_inventory_unit_path(company.units.first))

      get admin_inventory_suppliers_path
      expect(response.body).to include(new_admin_inventory_supplier_path)
    end
  end

  context "a manager whose owner revoked it" do
    before do
      revoke_settings!
      sign_in manager
    end

    it "still reads every setup screen" do
      [
        admin_inventory_units_path,
        admin_inventory_ingredient_categories_path,
        admin_inventory_suppliers_path,
        admin_inventory_ingredients_path,
        admin_inventory_ingredient_availabilities_path,
        admin_inventory_ingredient_path(ingredient),
        admin_inventory_supplier_path(supplier)
      ].each do |path|
        get path
        expect(response).to have_http_status(:ok), "expected #{path} to still be readable"
      end
    end

    it "cannot create or edit a unit" do
      expect { post admin_inventory_units_path, params: { unit: { name: "20kg sack" } } }
        .not_to change(company.units, :count)
      expect(response).to have_http_status(:redirect)

      get edit_admin_inventory_unit_path(company.units.first)
      expect(response).to have_http_status(:redirect)
    end

    it "cannot create or edit a category" do
      expect { post admin_inventory_ingredient_categories_path, params: { ingredient_category: { name: "Dairy" } } }
        .not_to change(IngredientCategory, :count)

      patch admin_inventory_ingredient_category_path(category), params: { ingredient_category: { name: "Fats" } }
      expect(category.reload.name).to eq("Oils")
    end

    it "cannot create or edit a vendor" do
      expect { post admin_inventory_suppliers_path, params: { supplier: { name: "Delta Foods" } } }
        .not_to change(Supplier, :count)

      patch admin_inventory_supplier_path(supplier), params: { supplier: { name: "Nile Foods Co" } }
      expect(supplier.reload.name).to eq("Nile Foods")
    end

    it "cannot create or edit an ingredient" do
      get new_admin_inventory_ingredient_path
      expect(response).to have_http_status(:redirect)

      patch admin_inventory_ingredient_path(ingredient), params: { ingredient: { name: "Butter" } }
      expect(ingredient.reload.name).to eq("Ghee")
    end

    it "cannot attach a vendor to an ingredient" do
      expect do
        post admin_inventory_ingredient_supplier_ingredients_path(ingredient),
          params: { supplier_ingredient: { supplier_id: supplier.id, price_dollars: "10" } }
      end.not_to change(SupplierIngredient, :count)
    end

    it "hides the add / edit controls it can no longer use" do
      get admin_inventory_units_path
      expect(response.body).not_to include(edit_admin_inventory_unit_path(company.units.first))

      get admin_inventory_suppliers_path
      expect(response.body).not_to include(new_admin_inventory_supplier_path)

      get admin_inventory_ingredients_path
      expect(response.body).not_to include(new_admin_inventory_ingredient_path)
    end

    it "can still move stock — that is inventory:manage, not setup" do
      location = create(:location, :central_kitchen, company: company)
      expect do
        post adjust_admin_inventory_ingredient_path(ingredient), params: {
          location_id: location.id, quantity_delta: "5", unit: "kg",
          adjustment_type: StockAdjustment::ADJUSTMENT_TYPES.first, reason_notes: "restock"
        }
      end.to change(StockAdjustment, :count).by(1)
    end
  end
end
