# frozen_string_literal: true

module Accounting
  # One cost-of-sales row per branch per business day, written beside that day's
  # sales entry.
  #
  # This used to be a row per completed order. The row carries no treasury, so it
  # raises no journal entry and never reaches the P&L — stock is expensed when it
  # is bought, and charging it again when it is sold would count the same cost
  # twice. That makes it a management figure, and a management figure does not
  # need a row per ticket: at a few hundred orders a day it buried the expenses
  # list without saying anything the day's total doesn't. Recognising it per
  # branch-day also puts cost on the same footing as revenue, which has posted
  # that way since `record_daily_sales!`.
  #
  # Costed the way FoodCostService costs — units sold per menu item times that
  # item's recipe cost at the ingredient's standard cost — so the food-cost report
  # and this row quote the same number. Re-running replaces the day's row, so
  # backfilling a range stays idempotent.
  class DailyCogsService
    CATEGORY_NAME = "COGS"

    def self.call(location:, business_date:, user:)
      new(location: location, business_date: business_date, user: user).call
    end

    def initialize(location:, business_date:, user:)
      @location = location
      @business_date = business_date.to_date
      @user = user
    end

    def call
      category = ExpenseCategory.find_by(name: CATEGORY_NAME)
      return if category.nil?

      existing = existing_row(category)

      # A day that sold nothing costed, or whose orders were all voided on a
      # re-run, must not keep yesterday's figure standing.
      if cost_of_sales_cents.zero?
        existing&.destroy
        return
      end

      existing ? existing.update!(attributes(category)) : Expense.create!(attributes(category))
    end

    private

    def attributes(category)
      {
        expense_category: category,
        user: @user,
        description: I18n.t(
          "accounting.expenses.auto.daily_cogs",
          location: @location.name,
          date: @business_date,
          default: "Cost of sales — #{@location.name} #{@business_date}"
        ),
        amount_cents: cost_of_sales_cents,
        expense_date: @business_date,
        recurrence: "one_time",
        is_auto_generated: true,
        source_record: @location
      }
    end

    def existing_row(category)
      Expense.where(
        expense_category_id: category.id,
        source_record: @location,
        expense_date: @business_date,
        is_auto_generated: true
      ).first
    end

    def cost_of_sales_cents
      @cost_of_sales_cents ||= calculate_cost_of_sales_cents
    end

    def calculate_cost_of_sales_cents
      units = units_sold_by_menu_item
      return 0 if units.empty?

      # Not `MenuItem.available` — an item sold that day still cost what it cost
      # after someone takes it off the menu.
      MenuItem.where(id: units.keys).includes(recipes: :ingredient).sum do |item|
        unit_cost_cents(item) * units.fetch(item.id, 0)
      end
    end

    def units_sold_by_menu_item
      OrderItem.where(order_id: completed_orders.select(:id))
               .where.not(menu_item_id: nil)
               .group(:menu_item_id)
               .sum(:quantity)
    end

    def unit_cost_cents(item)
      item.recipes.sum do |recipe|
        (recipe.base_quantity_used * recipe.ingredient.cost_per_unit_cents).round
      end
    end

    # The same orders the day's sales entry recognises, so cost and revenue can
    # never be drawn from different sets.
    def completed_orders
      Order.completed.where(
        created_at: BusinessDay.range(@business_date, location: @location),
        location_id: @location.id
      )
    end
  end
end
