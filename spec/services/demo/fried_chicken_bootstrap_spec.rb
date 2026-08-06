# frozen_string_literal: true

require "rails_helper"

RSpec.describe Demo::FriedChickenBootstrap do
  it "creates an isolated demo company without touching other tenants" do
    existing = create(:company, slug: "prod-tenant", name: "Production")
    Current.company = existing
    existing_item_count = MenuItem.unscoped.where(company_id: existing.id).count

    result = described_class.call(slug: "demo-fried-chicken", password: "demo-pass-99")

    expect(result.company.slug).to eq("demo-fried-chicken")
    expect(result.owner_email).to eq("owner@demo-fried-chicken.demo")

    demo_users = User.unscoped.where(company_id: result.company.id).pluck(:email)
    expect(demo_users).to include(
      "owner@demo-fried-chicken.demo",
      "manager@demo-fried-chicken.demo",
      "cashier@demo-fried-chicken.demo",
      "kitchen@demo-fried-chicken.demo"
    )

    expect(MenuItem.unscoped.where(company_id: result.company.id, available: true).count).to be > 10
    expect(MenuItem.unscoped.where(company_id: existing.id).count).to eq(existing_item_count)
    expect(User.unscoped.where(company_id: existing.id).where("email LIKE ?", "%demo-fried-chicken%")).to be_empty
  end

  it "rejects duplicate slugs" do
    create(:company, slug: "demo-fried-chicken")
    expect {
      described_class.call(slug: "demo-fried-chicken")
    }.to raise_error(ArgumentError, /already exists/)
  end
end
