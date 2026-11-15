# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Locations::DeliveryAreas", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:manager) { create(:user, :manager, company: company) }
  # Runs the floor and has admin access, but not locations:manage.
  let(:sub_manager) { create(:user, company: company, role: "sub_manager") }
  let(:branch) { create(:location, company: company, name: "Downtown") }

  before { Current.company = company }

  def area(attrs = {})
    DeliveryArea.create!({ location: branch, name: "Area #{SecureRandom.hex(3)}", fee_cents: 1000 }.merge(attrs))
  end

  describe "GET index" do
    before { sign_in manager }

    it "lists this branch's areas with their fees, and not another branch's" do
      area(name: "Maadi", name_ar: "المعادي", fee_cents: 2550)
      DeliveryArea.create!(location: create(:location, company: company), name: "Elsewhere")

      get admin_location_delivery_areas_path(branch)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Maadi", "المعادي", "25.50")
      expect(response.body).not_to include("Elsewhere")
    end

    it "filters by name and by status" do
      area(name: "Maadi")
      area(name: "Zamalek", active: false)

      get admin_location_delivery_areas_path(branch, q: "maa")
      expect(response.body).to include("Maadi")
      expect(response.body).not_to include("Zamalek")

      get admin_location_delivery_areas_path(branch, status: "inactive")
      expect(response.body).to include("Zamalek")
      expect(response.body).not_to include(">Maadi<")
    end

    it "sorts by a chosen column and ignores an unknown one" do
      area(name: "Cheap", fee_cents: 500, position: 2)
      area(name: "Pricey", fee_cents: 5000, position: 1)

      get admin_location_delivery_areas_path(branch, sort: "fee_cents", dir: "desc")
      expect(response.body.index("Pricey")).to be < response.body.index("Cheap")

      get admin_location_delivery_areas_path(branch, sort: "fee_cents", dir: "asc")
      expect(response.body.index("Cheap")).to be < response.body.index("Pricey")

      get admin_location_delivery_areas_path(branch, sort: "drop table")
      expect(response).to have_http_status(:ok)
      expect(response.body.index("Pricey")).to be < response.body.index("Cheap") # position asc
    end

    it "pages after 25 areas" do
      26.times { |i| area(name: format("Area %02d", i), position: i) }

      get admin_location_delivery_areas_path(branch)
      expect(response.body).to include("Area 24")
      expect(response.body).not_to include("Area 25")

      get admin_location_delivery_areas_path(branch, page: 2)
      expect(response.body).to include("Area 25")
    end

    it "is not found for a central kitchen" do
      kitchen = create(:location, :central_kitchen, company: company)
      get admin_location_delivery_areas_path(kitchen)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "create" do
    before { sign_in manager }

    it "adds an area, reading the fee in pounds with Arabic digits normalised client-side" do
      expect do
        post admin_location_delivery_areas_path(branch),
             params: { delivery_area: { name: "Dokki", name_ar: "الدقي", fee_pounds: "17.5", position: "3", active: "1" } }
      end.to change(DeliveryArea, :count).by(1)

      created = DeliveryArea.last
      expect(created.location).to eq(branch)
      expect(created.fee_cents).to eq(1750)
      expect(response).to redirect_to(admin_location_delivery_areas_path(branch))
    end

    it "stores a blank fee as free delivery" do
      post admin_location_delivery_areas_path(branch), params: { delivery_area: { name: "Free", fee_pounds: "" } }
      expect(DeliveryArea.last.fee_cents).to eq(0)
    end

    it "re-renders the form on a bad entry" do
      post admin_location_delivery_areas_path(branch), params: { delivery_area: { name: "", fee_pounds: "5" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "update and destroy" do
    before { sign_in manager }

    it "updates the fee and can deactivate" do
      a = area(name: "Maadi", fee_cents: 1000)
      patch admin_location_delivery_area_path(branch, a), params: { delivery_area: { fee_pounds: "30", active: "0" } }
      a.reload
      expect(a.fee_cents).to eq(3000)
      expect(a).not_to be_active
    end

    it "deletes an area" do
      a = area
      expect { delete admin_location_delivery_area_path(branch, a) }.to change(DeliveryArea, :count).by(-1)
    end

    it "cannot reach another branch's area through this branch" do
      other = DeliveryArea.create!(location: create(:location, company: company), name: "Elsewhere")
      patch admin_location_delivery_area_path(branch, other), params: { delivery_area: { fee_pounds: "1" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "without locations:manage" do
    before { sign_in sub_manager }

    it "refuses the list and changes" do
      get admin_location_delivery_areas_path(branch)
      expect(response).to have_http_status(:redirect)

      expect do
        post admin_location_delivery_areas_path(branch), params: { delivery_area: { name: "Sneaky" } }
      end.not_to change(DeliveryArea, :count)
    end
  end
end
