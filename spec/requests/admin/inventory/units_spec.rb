# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::Units", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "lists units including the seeded built-ins" do
    get admin_inventory_units_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("gallons")
  end

  it "creates a custom unit" do
    expect do
      post admin_inventory_units_path, params: { unit: { name: "20kg sack" } }
    end.to change(company.units, :count).by(1)
    expect(company.units.find_by(name: "20kg sack").system).to be(false)
  end

  it "removes a custom unit but refuses to delete a built-in one" do
    custom = company.units.create!(name: "tin")
    expect { delete admin_inventory_unit_path(custom) }.to change(company.units, :count).by(-1)

    builtin = company.units.find_by(name: "kg")
    expect { delete admin_inventory_unit_path(builtin) }.not_to change(company.units, :count)
    expect(flash[:alert]).to be_present
  end

  it "does not rename a built-in unit even if forced" do
    builtin = company.units.find_by(name: "kg")
    patch admin_inventory_unit_path(builtin), params: { unit: { name: "kilos" } }
    expect(builtin.reload.name).to eq("kg")
  end
end
