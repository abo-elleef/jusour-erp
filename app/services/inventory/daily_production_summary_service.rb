# frozen_string_literal: true

module Inventory
  # Groups active manufacturing runs for one day by output ingredient.
  #
  # Pass `templates:` to also emit a zero row for every template output that
  # produced nothing that day — so the sheet reads as a checklist of everything
  # that could have been made, rather than only what was.
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
      :template_position,
      keyword_init: true
    )

    def initialize(runs:, templates: nil)
      @runs = Array(runs)
      @templates = templates
    end

    def call
      rows = @runs
        .group_by { |run| run.manufacturing_template.output_ingredient_id }
        .map { |_id, group| build_row(group) }

      rows += zero_rows(rows) unless @templates.nil?
      # Follow the order the templates are arranged in (the drag order on the
      # templates page), not the alphabet — that sequence is how the kitchen works
      # through the day. Name only breaks ties.
      rows.sort_by { |row| [row.template_position, row.ingredient.name.to_s.downcase] }
    end

    private

    # Templates whose output saw no production. Grouped by output ingredient so
    # several templates feeding one ingredient still yield a single row, matching
    # how the produced rows are keyed.
    def zero_rows(produced)
      covered = produced.map { |row| row.ingredient.id }
      Array(@templates)
        .reject { |template| covered.include?(template.output_ingredient_id) }
        .group_by(&:output_ingredient_id)
        .map { |_id, group| zero_row(group) }
    end

    def zero_row(group)
      template = group.first
      ingredient = template.output_ingredient
      Row.new(
        ingredient: ingredient,
        total_quantity: 0,
        unit: template.yield_unit.presence || ingredient.unit,
        run_count: 0,
        runs: [],
        locations: [],
        expires_on_dates: [],
        notes: [],
        template_position: min_position(group)
      )
    end

    # Several templates can feed one output ingredient; the earliest of them decides
    # where the row sits.
    def min_position(templates)
      Array(templates).map { |template| template.position.to_i }.min || 0
    end

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
        notes: group.filter_map { |run| run.notes.presence }.uniq,
        template_position: min_position(group.map(&:manufacturing_template))
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
