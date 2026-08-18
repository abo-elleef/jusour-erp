# frozen_string_literal: true

module Inventory
  # Groups active manufacturing runs for one day by output ingredient.
  class DailyProductionSummaryService
    Row = Struct.new(
      :ingredient,
      :total_quantity,
      :unit,
      :run_count,
      :runs,
      :locations,
      :expires_on_dates,
      :notes,
      keyword_init: true
    )

    def initialize(runs:)
      @runs = Array(runs)
    end

    def call
      @runs
        .group_by { |run| run.manufacturing_template.output_ingredient_id }
        .map { |_id, group| build_row(group) }
        .sort_by { |row| row.ingredient.name.to_s.downcase }
    end

    private

    def build_row(group)
      ingredient = group.first.manufacturing_template.output_ingredient
      unit = display_unit_for(group, ingredient)
      total = group.sum { |run| produced_in_unit(run, ingredient, unit) }

      Row.new(
        ingredient: ingredient,
        total_quantity: total,
        unit: unit,
        run_count: group.size,
        runs: group.sort_by(&:created_at),
        locations: group.filter_map { |run| run.location&.name }.uniq,
        expires_on_dates: group.map(&:output_expires_on).uniq.sort,
        notes: group.filter_map { |run| run.notes.presence }.uniq
      )
    end

    def display_unit_for(group, ingredient)
      units = group.map { |run| run.manufacturing_template.yield_unit.presence || ingredient.unit }
      units.tally.max_by { |_unit, count| count }&.first || ingredient.unit
    end

    # Convert each run's output into the row's display unit so mixed-template
    # days still sum correctly. Template yield is stored in yield_unit.
    def produced_in_unit(run, ingredient, display_unit)
      base = run.runs_count.to_d * run.manufacturing_template.base_yield_quantity
      ingredient.from_base(base, display_unit)
    rescue ArgumentError
      run.runs_count.to_d * run.manufacturing_template.yield_quantity.to_d
    end
  end
end
