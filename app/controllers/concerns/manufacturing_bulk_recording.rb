# frozen_string_literal: true

# Shared loader/submitter for the excel-style bulk production sheet
# (admin inventory + kitchen production screen).
module ManufacturingBulkRecording
  extend ActiveSupport::Concern

  included do
    helper_method :bulk_row_value, :can_transfer_manufacturing_batch?
  end

  private

  def load_manufacturing_bulk_sheet
    @templates = ManufacturingTemplate.active
      .includes(:output_ingredient, :main_ingredient, manufacturing_template_lines: :ingredient)
      .ordered
      .select { |template| template.manufacturing_template_lines.any? }
    @production_locations = bulk_production_locations
    @default_production_location_id = (
      @production_locations.find { |location| location.central_kitchen? && location.default_production_location? } ||
      @production_locations.find(&:central_kitchen?)
    )&.id
    @bulk = params[:bulk] || ActionController::Parameters.new
  end

  def bulk_production_locations
    Location.active.central_kitchens.ordered.to_a + Location.active.branches.ordered.to_a
  end

  def bulk_occurred_on
    date = (Date.parse(bulk_param(:occurred_on).to_s) rescue Date.current)
    [date, Date.current].min
  end

  def bulk_param(key)
    params.dig(:bulk, key)
  end

  def bulk_row_params
    raw = params.dig(:bulk, :rows)
    return [] if raw.blank?

    raw.to_unsafe_h.values
  end

  def bulk_location
    id = bulk_param(:location_id).to_s
    bulk_production_locations.find { |location| location.id.to_s == id }
  end

  def bulk_row_value(template, key, default = nil)
    params.dig(:bulk, :rows, template.id.to_s, key.to_s).presence || default
  end

  # Remembers the batch just recorded (as a one-shot flash) so the next page
  # load can offer to transfer it out in one step instead of line by line.
  def remember_batch_for_transfer(runs, location)
    flash[:batch_run_ids] = runs.map(&:id)
    flash[:batch_location_id] = location&.id
  end

  # Mirrors exactly what ProductionController#transfer_batch requires: anyone
  # who can record production can also transfer what they just made — kitchen
  # staff included, not just owners/managers with full inventory access.
  def can_transfer_manufacturing_batch?
    current_user&.can_access_production? || false
  end
end
