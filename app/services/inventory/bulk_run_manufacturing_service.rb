# frozen_string_literal: true

module Inventory
  class BulkRunManufacturingService
    class Error < StandardError; end

    def initialize(user:, location:, occurred_on:, rows:, default_shelf_life_days: nil)
      @user = user
      @location = location
      @occurred_on = occurred_on
      @default_shelf_life_days = default_shelf_life_days.presence&.to_i
      @rows = Array(rows)
    end

    def call
      raise Error, I18n.t("production.location_required") if @location.blank?

      entries = prepared_entries
      raise Error, I18n.t("production.bulk.none_filled") if entries.empty?

      runs = []
      ActiveRecord::Base.transaction do
        entries.each do |attrs|
          runs << RunManufacturingService.new(**attrs).call
        end
      end
      runs
    end

    private

    def prepared_entries
      @rows.filter_map do |raw|
        row = raw.to_h.stringify_keys
        template = allowed_templates[row["template_id"].to_s]
        next if template.blank?
        next if quantity_blank?(row, template)

        {
          template: template,
          user: @user,
          location: @location,
          occurred_on: @occurred_on,
          notes: row["notes"].presence,
          shelf_life_days: shelf_life_for(row, template),
          runs_count: row["runs_count"],
          main_input_quantity: row["main_input_quantity"],
          main_input_unit: row["main_input_unit"]
        }
      end
    end

    def quantity_blank?(row, template)
      if template.main_ingredient_controlled?
        row["main_input_quantity"].blank?
      else
        row["runs_count"].blank?
      end
    end

    def shelf_life_for(row, template)
      row["shelf_life_days"].presence ||
        @default_shelf_life_days ||
        template.output_ingredient.shelf_life_days
    end

    def allowed_templates
      @allowed_templates ||= ManufacturingTemplate.active
        .includes(:output_ingredient, :main_ingredient, manufacturing_template_lines: :ingredient)
        .select { |template| template.manufacturing_template_lines.any? }
        .index_by { |template| template.id.to_s }
    end
  end
end
