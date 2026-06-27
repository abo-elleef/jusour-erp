# frozen_string_literal: true

require "rails_helper"

RSpec.describe Income, type: :model do
  let(:owner) do
    User.create!(
      name: "Owner",
      email: "income-owner@example.com",
      role: "owner",
      password: "password123"
    )
  end

  let(:category) do
    IncomeCategory.create!(name: "Test Income", category_type: "other")
  end

  let(:treasury) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer")
  end

  it "is valid with required attributes" do
    income = described_class.new(
      income_category: category,
      user: owner,
      treasury: treasury,
      description: "Consulting fee",
      amount_cents: 50_000,
      income_date: Date.current
    )

    expect(income).to be_valid
  end
end

RSpec.describe IncomeCategory, type: :model do
  it "prevents deleting system-managed categories" do
    category = described_class.create!(
      name: "System Sales",
      category_type: "sales",
      system_managed: true
    )

    expect(category.destroy).to be_falsey
    expect(described_class.exists?(category.id)).to be true
  end
end
