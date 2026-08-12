# frozen_string_literal: true

module Inventory
  class RunManufacturingService
    class Error < StandardError; end

    def initialize(template:, user:, location:, shelf_life_days:, runs_count: nil,
                   main_input_quantity: nil, main_input_unit: nil, occurred_on: Date.current, notes: nil)
      @template = template
      @user = user
      @location = location
      @shelf_life_days = shelf_life_days.to_i
      @main_input_quantity = main_input_quantity.presence && main_input_quantity.to_d
      @main_input_unit = main_input_unit.presence
      # In main-ingredient mode the run count is derived from the entered amount;
      # otherwise it's whatever the operator typed.
      @runs_count = @template.main_ingredient_controlled? ? derived_runs_count : runs_count.to_d
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
          location: @location,
          runs_count: @runs_count,
          main_input_quantity: @main_input_quantity,
          main_input_unit: @main_input_unit,
          occurred_on: @occurred_on,
          shelf_life_days: @shelf_life_days,
          notes: @notes
        )

        total_input_cost_cents = 0

        @template.manufacturing_template_lines.includes(:ingredient).each do |line|
          quantity = line.base_quantity_used * @runs_count
          total_input_cost_cents += (quantity * line.ingredient.cost_per_unit_cents).round
          deduct_input!(line.ingredient, quantity, run)
          affected_ingredient_ids << line.ingredient_id
        end

        output_quantity = @template.base_yield_quantity * @runs_count
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

    # runs_count implied by the entered main-ingredient amount and the recipe
    # ratio: received_main ÷ main_per_batch (both in the ingredient's base unit).
    def derived_runs_count
      line = @template.main_line
      return 0.to_d if line.nil? || @main_input_quantity.nil?

      per_run_base = line.base_quantity_used
      return 0.to_d unless per_run_base&.positive?

      main_base = @template.main_ingredient.to_base(@main_input_quantity, @main_input_unit)
      main_base / per_run_base
    rescue ArgumentError
      0.to_d
    end

    def validate!
      if @template.main_ingredient_controlled?
        raise Error, I18n.t("production.main_not_configured") if @template.main_line.nil?
        raise Error, I18n.t("production.invalid_main_quantity") if @main_input_quantity.nil? || @main_input_quantity <= 0
      end
      raise Error, I18n.t("production.invalid_runs") unless @runs_count.positive?
      raise Error, I18n.t("production.invalid_shelf_life") unless @shelf_life_days.positive?
      raise Error, I18n.t("production.no_input_lines") if @template.manufacturing_template_lines.empty?
      raise Error, I18n.t("production.location_required") if @location.blank?
    end

    # Consume the input from this location's FIFO batches, and record the
    # consumption against the location so its on-hand drops too.
    def deduct_input!(ingredient, quantity, run)
      remaining = quantity

      ingredient.stock_batches.where(location: @location).fifo_order.with_stock.each do |batch|
        break if remaining <= 0

        deductable = [batch.quantity_remaining.to_d, remaining].min
        batch.update!(quantity_remaining: batch.quantity_remaining.to_d - deductable)
        remaining -= deductable
      end

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @user,
        location: @location,
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
        location: @location,
        quantity_received: output_quantity,
        quantity_remaining: output_quantity,
        cost_per_unit_cents: cost_per_unit_cents,
        received_on: @occurred_on,
        expires_on: @occurred_on + @shelf_life_days.days,
        batch_reference: run.run_number
      )

      StockAdjustment.create!(
        ingredient: output_ingredient,
        user: @user,
        location: @location,
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
