# frozen_string_literal: true

class ProductionController < ApplicationController
  before_action :require_production_access!
  layout "kitchen"

  def index
    authorize :production, :index?, policy_class: ProductionPolicy
    @templates = ManufacturingTemplate.active
      .includes(:output_ingredient, manufacturing_template_lines: :ingredient)
      .ordered
      .select { |template| template.manufacturing_template_lines.any? }
    @production_locations = production_locations
    @default_production_location_id = @production_locations.find(&:central_kitchen?)&.id
  end

  def create
    @template = ManufacturingTemplate.active.find(params[:manufacturing_template_id])
    authorize @template, :create?, policy_class: ProductionPolicy

    runs_count = params[:runs_count].to_d
    if runs_count <= 0
      redirect_to production_path, alert: t("production.invalid_runs")
      return
    end

    shelf_life_days = params[:shelf_life_days].to_i
    if shelf_life_days <= 0
      redirect_to production_path, alert: t("production.invalid_shelf_life")
      return
    end

    location = production_locations.find { |l| l.id == params[:location_id] }
    if location.blank?
      redirect_to production_path, alert: t("production.location_required")
      return
    end

    run = ::Inventory::RunManufacturingService.new(
      template: @template,
      user: current_user,
      location: location,
      runs_count: runs_count,
      shelf_life_days: shelf_life_days,
      occurred_on: production_date(params[:occurred_on]),
      notes: params[:notes].presence
    ).call

    redirect_to production_path, notice: t("production.success", number: run.run_number)
  rescue Inventory::RunManufacturingService::Error => e
    redirect_to production_path, alert: e.message
  end

  private

  # The production date: defaults to today, never in the future.
  def production_date(raw)
    date = (Date.parse(raw.to_s) rescue Date.current)
    [date, Date.current].min
  end

  # Central kitchens first (the usual production site), then branches.
  def production_locations
    Location.active.central_kitchens.ordered.to_a + Location.active.branches.ordered.to_a
  end

  def require_production_access!
    return if current_user&.can_access_production?

    flash[:alert] = t("flash.production_access")
    redirect_to root_path
  end
end
