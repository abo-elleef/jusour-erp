# frozen_string_literal: true

# Backfill system-managed "Goods delivery" expense category for courier freight
# on vendor invoices. New companies get it via seeds / demo bootstrap / specs.
class SeedGoodsDeliveryExpenseCategory < ActiveRecord::Migration[7.1]
  def up
    Company.find_each do |company|
      ExpenseCategory.find_or_create_by!(name: "Goods delivery", company: company) do |category|
        category.category_type = "other"
        category.system_managed = true
        category.position = 0
      end
    end
  end

  def down
    # Leave seeded rows in place.
  end
end
