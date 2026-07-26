# frozen_string_literal: true

module Accounting
  class AutoCostService
    def initialize(order)
      @order = order
    end

    def call
      cogs_category = ExpenseCategory.find_by!(name: "COGS")

      ingredient_cost_cents = @order.order_items.includes(menu_item: { recipes: :ingredient }).sum do |item|
        next 0 unless item.menu_item_id

        item.menu_item.recipes.sum do |recipe|
          (recipe.base_quantity_used * item.quantity * recipe.ingredient.cost_per_unit_cents).round
        end
      end

      return if ingredient_cost_cents.zero?

      Expense.create!(
        expense_category: cogs_category,
        user: @order.user,
        description: "COGS — Order ##{@order.order_number}",
        amount_cents: ingredient_cost_cents,
        expense_date: BusinessDay.for(@order.created_at),
        recurrence: "one_time",
        is_auto_generated: true,
        source_record: @order
      )
    end
  end
end
