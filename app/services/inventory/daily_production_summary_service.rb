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
      total = group.sum do |run|
        run.runs_count.to_d * run.manufacturing_template.yield_quantity.to_d
      end

      Row.new(
        ingredient: ingredient,
        total_quantity: total,
        unit: ingredient.unit,
        run_count: group.size,
        runs: group.sort_by(&:created_at),
        locations: group.filter_map { |run| run.location&.name }.uniq,
        expires_on_dates: group.map(&:output_expires_on).uniq.sort,
        notes: group.filter_map { |run| run.notes.presence }.uniq
      )
    end
  end
end
