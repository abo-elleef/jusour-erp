# frozen_string_literal: true

module Inventory
  class RunManufacturingService
    class Error < StandardError; end

    def initialize(template:, user:, runs_count:, shelf_life_days:, occurred_on: Date.current, notes: nil)
      @template = template
      @user = user
      @runs_count = runs_count.to_d
      @shelf_life_days = shelf_life_days.to_i
      @occurred_on = occurred_on
      @notes = notes
    end

    def call
      validate!

      run = nil
      affected_ingredient_ids = []

      ActiveRecord::Base.transaction do
        run = ManufacturingRun.create!(
          manufacturing_template: @template,
          user: @user,
          runs_count: @runs_count,
          occurred_on: @occurred_on,
          shelf_life_days: @shelf_life_days,
          notes: @notes
        )

        total_input_cost_cents = 0

        @template.manufacturing_template_lines.includes(:ingredient).each do |line|
          quantity = line.quantity_used.to_d * @runs_count
          total_input_cost_cents += (quantity * line.ingredient.cost_per_unit_cents).round
          deduct_input!(line.ingredient, quantity, run)
          affected_ingredient_ids << line.ingredient_id
        end

        output_quantity = @template.yield_quantity.to_d * @runs_count
        add_output!(output_quantity, total_input_cost_cents, run)
        affected_ingredient_ids << @template.output_ingredient_id
      end

      affected_ingredient_ids.uniq.each do |ingredient_id|
        ingredient = Ingredient.find(ingredient_id)
        Inventory::CheckLowStockJob.perform_later(ingredient_id) if ingredient.low_stock?
      end

      run
    end

    private

    def validate!
      raise Error, "Runs count must be positive" unless @runs_count.positive?
      raise Error, "Shelf life must be at least 1 day" unless @shelf_life_days.positive?
      raise Error, "Template has no input lines" if @template.manufacturing_template_lines.empty?
    end

    def deduct_input!(ingredient, quantity, run)
      remaining = quantity

      ingredient.stock_batches.fifo_order.with_stock.each do |batch|
        break if remaining <= 0

        deductable = [batch.quantity_remaining.to_d, remaining].min
        batch.update!(quantity_remaining: batch.quantity_remaining.to_d - deductable)
        remaining -= deductable
      end

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @user,
        quantity_delta: -quantity,
        adjustment_type: "production_consumption",
        reason_notes: consumption_note(run, ingredient)
      )
    end

    def add_output!(output_quantity, total_input_cost_cents, run)
      output_ingredient = @template.output_ingredient
      cost_per_unit_cents = if output_quantity.positive?
                              (total_input_cost_cents.to_d / output_quantity).round
                            else
                              0
                            end

      batch = StockBatch.create!(
        ingredient: output_ingredient,
        quantity_received: output_quantity,
        quantity_remaining: output_quantity,
        cost_per_unit_cents: cost_per_unit_cents,
        received_on: @occurred_on,
        expires_on: @occurred_on + @shelf_life_days.days,
        batch_reference: "MFG-#{run.id.to_s.first(8).upcase}"
      )

      StockAdjustment.create!(
        ingredient: output_ingredient,
        user: @user,
        stock_batch: batch,
        quantity_delta: output_quantity,
        adjustment_type: "production_output",
        reason_notes: output_note(run)
      )
    end

    def consumption_note(run, ingredient)
      I18n.t(
        "inventory.manufacturing.adjustment_consumption",
        template: @template.name,
        ingredient: ingredient.name,
        runs: @runs_count,
        run_id: run.id
      )
    end

    def output_note(run)
      I18n.t(
        "inventory.manufacturing.adjustment_output",
        template: @template.name,
        output: @template.output_ingredient.name,
        runs: @runs_count,
        run_id: run.id
      )
    end
  end
end
