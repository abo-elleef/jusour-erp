# frozen_string_literal: true

require "rails_helper"

# Stable, stored account codes for income/expense categories (4001+ / 5001+),
# assigned once at creation like Partner/Loan.
RSpec.describe "Category account codes" do
  let(:company) { create(:company) }

  before { Current.company = company }

  describe IncomeCategory do
    it "assigns sequential codes starting at 4001" do
      a = IncomeCategory.create!(name: "Alpha", category_type: "sales")
      b = IncomeCategory.create!(name: "Beta", category_type: "services")
      expect(a.account_code).to eq(4001)
      expect(b.account_code).to eq(4002)
    end

    it "keeps the code fixed when the category is renamed" do
      cat = IncomeCategory.create!(name: "Alpha", category_type: "sales")
      code = cat.account_code
      cat.update!(name: "Renamed")
      expect(cat.reload.account_code).to eq(code)
    end

    it "requires a unique code per company" do
      IncomeCategory.create!(name: "Alpha", category_type: "sales")
      dup = IncomeCategory.new(name: "Beta", category_type: "services", account_code: 4001)
      expect(dup).not_to be_valid
      expect(dup.errors[:account_code]).to be_present
    end
  end

  describe ExpenseCategory do
    it "assigns sequential codes starting at 5001" do
      a = ExpenseCategory.create!(name: "Alpha", category_type: "cogs")
      b = ExpenseCategory.create!(name: "Beta", category_type: "rent")
      expect(a.account_code).to eq(5001)
      expect(b.account_code).to eq(5002)
    end
  end
end
