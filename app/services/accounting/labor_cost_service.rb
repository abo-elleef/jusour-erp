# frozen_string_literal: true

module Accounting
  class LaborCostService
    def initialize(shift_log)
      @shift = shift_log
    end

    def call
      return unless @shift.clocked_out_at

      labor_category = ExpenseCategory.find_by!(name: "Labor")
      hours_worked = @shift.hours_worked
      labor_cost_cents = (hours_worked * @shift.hourly_rate_cents).round
      return if labor_cost_cents.zero?

      Expense.create!(
        expense_category: labor_category,
        user: @shift.user,
        description: labor_description,
        amount_cents: labor_cost_cents,
        expense_date: @shift.clocked_in_at.to_date,
        recurrence: "one_time",
        is_auto_generated: true,
        source_record: @shift
      )
    end

    private

    def labor_description
      start_fmt = @shift.clocked_in_at.strftime("%b %d, %I:%M%p")
      end_fmt = @shift.clocked_out_at.strftime("%I:%M%p")
      "Labor — #{@shift.user.name} shift (#{start_fmt} – #{end_fmt})"
    end
  end
end
