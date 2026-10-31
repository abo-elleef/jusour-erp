# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::Suppliers index balance toggle", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  def supplier(name, balance_cents, active: true)
    Supplier.create!(company: company, name: name, lead_time_days: 1, active: active).tap do |s|
      s.ap_treasury.update!(balance_cents: balance_cents)
    end
  end

  it "shows every supplier when off" do
    supplier("Owed Co", 5_000)
    supplier("Settled Co", 0)

    get admin_inventory_suppliers_path

    expect(response.body).to include("Owed Co", "Settled Co")
    expect(response.body).to include('aria-checked="false"')
  end

  it "keeps only suppliers whose balance is not zero, overpayments included" do
    supplier("Owed Co", 5_000)
    supplier("Overpaid Co", -2_000)
    supplier("Settled Co", 0)

    get admin_inventory_suppliers_path(balance: "nonzero")

    expect(response.body).to include("Owed Co", "Overpaid Co")
    expect(response.body).not_to include("Settled Co")
    expect(response.body).to include('aria-checked="true"')
  end

  it "combines with the status filter and keeps itself on the status links" do
    supplier("Active Owed", 5_000)
    supplier("Inactive Owed", 3_000, active: false)
    supplier("Inactive Settled", 0, active: false)

    get admin_inventory_suppliers_path(status: "inactive", balance: "nonzero")

    expect(response.body).to include("Inactive Owed")
    expect(response.body).not_to include("Inactive Settled")
    expect(response.body).not_to include("Active Owed")
    expect(response.body).to include("balance=nonzero&amp;dir=asc&amp;sort=name&amp;status=active")
  end

  it "turns off by dropping the param and keeping the rest" do
    get admin_inventory_suppliers_path(status: "all", balance: "nonzero")

    toggle = response.body[/<a[^>]*role="switch"[^>]*>/]
    expect(toggle).to include("status=all")
    expect(toggle).not_to include("balance=")
  end
end
