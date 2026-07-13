# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::Suppliers index sorting", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  # Positions in the rendered HTML tell us the row order.
  def order_of(names)
    body = response.body
    names.sort_by { |n| body.index(">#{n}<") || body.index(n) }
  end

  it "sorts by name ascending by default, and reverses with dir=desc" do
    Supplier.create!(company: company, name: "Zeta", lead_time_days: 1)
    Supplier.create!(company: company, name: "Alpha", lead_time_days: 9)

    get admin_inventory_suppliers_path
    expect(order_of(%w[Alpha Zeta])).to eq(%w[Alpha Zeta])

    get admin_inventory_suppliers_path(sort: "name", dir: "desc")
    expect(order_of(%w[Alpha Zeta])).to eq(%w[Zeta Alpha])
  end

  it "sorts by lead time" do
    Supplier.create!(company: company, name: "Slow", lead_time_days: 30)
    Supplier.create!(company: company, name: "Fast", lead_time_days: 2)

    get admin_inventory_suppliers_path(sort: "lead_time", dir: "asc")
    expect(order_of(%w[Fast Slow])).to eq(%w[Fast Slow])
  end

  it "ignores an unknown sort column (falls back to name)" do
    Supplier.create!(company: company, name: "Beta")
    Supplier.create!(company: company, name: "Aaa")

    get admin_inventory_suppliers_path(sort: "bogus")
    expect(response).to have_http_status(:ok)
    expect(order_of(%w[Aaa Beta])).to eq(%w[Aaa Beta])
  end
end
