# frozen_string_literal: true

require "rails_helper"

RSpec.describe Company, "#receipt_name", type: :model do
  let(:company) { create(:company, name: "Bazzar Dent") }

  it "uses the company's own name when no branch is given" do
    expect(company.receipt_name).to eq("Bazzar Dent")
  end

  it "uses the branch name when the branch has one" do
    branch = create(:location, company: company, name: "SAQR Cafe")

    expect(company.receipt_name(location: branch)).to eq("SAQR Cafe")
  end

  it "falls back to the company name when the branch name is blank" do
    branch = build(:location, company: company, name: "   ")

    expect(company.receipt_name(location: branch)).to eq("Bazzar Dent")
  end

  it "does not use the restaurant_name setting" do
    CompanySetting.create!(company: company, restaurant_name: "SAQR Fried Chicken")
    branch = create(:location, company: company, name: "SAQR Cafe")

    expect(company.reload.receipt_name).to eq("Bazzar Dent")
    expect(company.receipt_name(location: branch)).to eq("SAQR Cafe")
  end

  it "never falls back to the product name" do
    expect(company.receipt_name).not_to eq(I18n.t("app.name"))
  end
end
