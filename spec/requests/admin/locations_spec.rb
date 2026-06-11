# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Locations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, :manager, company: company) }
  let(:cashier) { create(:user, company: company) }

  before { Current.company = company }

  describe "GET /admin/locations" do
    context "as owner" do
      before { sign_in owner }

      it "lists locations" do
        create(:location, company: company, name: "Branch 1")
        create(:location, :central_kitchen, company: company)

        get admin_locations_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Branch 1")
        expect(response.body).to include("Central Kitchen")
      end
    end

    context "as cashier" do
      before { sign_in cashier }

      it "redirects to POS" do
        get admin_locations_path
        expect(response).to redirect_to(pos_path)
      end
    end
  end

  describe "GET /admin/locations/:id" do
    before { sign_in owner }

    it "shows location details with stock and menu items" do
      location = create(:location, company: company, name: "Downtown Branch")
      ingredient = create(:ingredient, company: company)
      create(:ingredient_location, location: location, ingredient: ingredient, quantity_on_hand: 8.0)
      menu_item = create(:menu_item, company: company)
      create(:location_menu_item, location: location, menu_item: menu_item, available: true)

      get admin_location_path(location)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Downtown Branch")
    end
  end

  describe "POST /admin/locations" do
    before { sign_in owner }

    it "creates a branch location" do
      post admin_locations_path, params: {
        location: {
          name: "East Branch",
          location_type: "branch",
          address: "123 Main St",
          active: true
        }
      }

      location = Location.last
      expect(location.name).to eq("East Branch")
      expect(location.branch?).to be true
      expect(response).to redirect_to(admin_location_path(location))
    end

    it "creates a central kitchen" do
      post admin_locations_path, params: {
        location: {
          name: "Main Kitchen",
          location_type: "central_kitchen",
          active: true
        }
      }

      location = Location.last
      expect(location.central_kitchen?).to be true
    end

    it "rejects duplicate names within same company" do
      create(:location, company: company, name: "Branch 1")

      post admin_locations_path, params: {
        location: { name: "Branch 1", location_type: "branch" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    context "as manager" do
      before { sign_in manager }

      it "is not authorized to create" do
        post admin_locations_path, params: {
          location: { name: "New Branch", location_type: "branch" }
        }
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "PATCH /admin/locations/:id" do
    before { sign_in owner }

    it "updates the location" do
      location = create(:location, company: company, name: "Old Name")

      patch admin_location_path(location), params: {
        location: { name: "New Name", location_type: "branch", active: true }
      }

      expect(location.reload.name).to eq("New Name")
      expect(response).to redirect_to(admin_location_path(location))
    end

    it "can deactivate a location" do
      location = create(:location, company: company, active: true)

      patch admin_location_path(location), params: {
        location: { name: location.name, location_type: location.location_type, active: false }
      }

      expect(location.reload.active).to be false
    end
  end

  describe "DELETE /admin/locations/:id" do
    before { sign_in owner }

    it "destroys the location" do
      location = create(:location, company: company)

      expect {
        delete admin_location_path(location)
      }.to change(Location, :count).by(-1)

      expect(response).to redirect_to(admin_locations_path)
    end
  end
end
