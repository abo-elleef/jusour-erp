# frozen_string_literal: true

require "rails_helper"

RSpec.describe Company, "#receipt_name", type: :model do
  let(:company) { create(:company, name: "Bazzar Dent") }

  it "uses the company's own name when no restaurant_name is set" do
    expect(company.receipt_name).to eq("Bazzar Dent")
  end

  it "prefers the restaurant_name setting when one is set" do
    CompanySetting.create!(company: company, restaurant_name: "SAQR Fried Chicken")

    expect(company.reload.receipt_name).to eq("SAQR Fried Chicken")
  end

  it "ignores a blank restaurant_name" do
    CompanySetting.create!(company: company, restaurant_name: "")

    expect(company.reload.receipt_name).to eq("Bazzar Dent")
  end

  it "never falls back to the product name" do
    expect(company.receipt_name).not_to eq(I18n.t("app.name"))
  end
end
