# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Locations::MenuItems", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before { Current.company = company }

  let!(:location) { create(:location, company: company, name: "Branch A") }
  let!(:category) { create(:category, company: company) }
  let!(:menu_item) { create(:menu_item, company: company, category: category) }

  before { sign_in owner }

  describe "GET /admin/locations/:location_id/menu_items" do
    it "lists all company menu items with availability for the location" do
      create(:location_menu_item, location: location, menu_item: menu_item, available: true)

      get admin_location_menu_items_path(location)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /admin/locations/:location_id/menu_items/:id" do
    it "toggles availability off for an existing location_menu_item" do
      lmi = create(:location_menu_item, location: location, menu_item: menu_item, available: true)

      patch admin_location_menu_item_path(location, menu_item), params: {
        location_menu_item: { available: false }
      }

      expect(lmi.reload.available).to be false
    end

    it "creates a location_menu_item if it does not exist yet" do
      expect {
        patch admin_location_menu_item_path(location, menu_item), params: {
          location_menu_item: { available: false }
        }
      }.to change(LocationMenuItem, :count).by(1)
    end

    it "sets a price override for the location" do
      patch admin_location_menu_item_path(location, menu_item), params: {
        location_menu_item: { available: true, price_override_dollars: "12.50" }
      }

      lmi = LocationMenuItem.find_by(location: location, menu_item: menu_item)
      expect(lmi.price_override_cents).to eq(1250)
    end
  end

  describe "POST /admin/locations/:location_id/menu_items/bulk_update" do
    it "enables multiple menu items at once" do
      item2 = create(:menu_item, company: company, category: category)

      post bulk_update_admin_location_menu_items_path(location), params: {
        menu_item_ids: [menu_item.id, item2.id],
        available: "true"
      }

      expect(LocationMenuItem.where(location: location, available: true).count).to eq(2)
      expect(response).to redirect_to(admin_location_menu_items_path(location))
    end
  end
end
