# frozen_string_literal: true

RSpec.configure do |config|
  config.before do
    Current.company = create(:company) unless Current.company

    ExpenseCategory.find_or_create_by!(name: "COGS", company: Current.company) do |category|
      category.category_type = "cogs"
      category.system_managed = true
      category.position = 1
    end

    ExpenseCategory.find_or_create_by!(name: "Vendor purchases", company: Current.company) do |category|
      category.category_type = "other"
      category.system_managed = true
      category.position = 0
    end

    ExpenseCategory.find_or_create_by!(name: "Goods delivery", company: Current.company) do |category|
      category.category_type = "other"
      category.system_managed = true
      category.position = 0
    end
  end

  config.after do
    Current.reset
  end
end
