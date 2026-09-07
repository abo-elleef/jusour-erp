# frozen_string_literal: true

class ProductionController < ApplicationController
  include FeatureGated
  include ManufacturingBulkRecording

  before_action { require_feature!(:manufacturing) }

  before_action :require_production_access!
  layout "kitchen"

  def index
    authorize :production, :index?, policy_class: ProductionPolicy
    load_manufacturing_bulk_sheet
  end

  def create
    @template = ManufacturingTemplate.active.find(params[:manufacturing_template_id])
    authorize @template, :create?, policy_class: ProductionPolicy

    location = production_locations.find { |l| l.id == params[:location_id] }
    if location.blank?
      redirect_to production_path, alert: t("production.location_required")
      return
    end

    run = ::Inventory::RunManufacturingService.new(
      template: @template,
      user: current_user,
      location: location,
      runs_count: params[:runs_count],
      main_input_quantity: params[:main_input_quantity],
      main_input_unit: params[:main_input_unit],
      shelf_life_days: params[:shelf_life_days].to_i,
      occurred_on: production_date(params[:occurred_on]),
      notes: params[:notes].presence
    ).call

    redirect_to production_path, notice: t("production.success", number: run.run_number)
  rescue Inventory::RunManufacturingService::Error => e
    redirect_to production_path, alert: e.message
  end

  def bulk_create
    authorize :production, :create?, policy_class: ProductionPolicy
    runs = ::Inventory::BulkRunManufacturingService.new(
      user: current_user,
      location: bulk_location,
      occurred_on: bulk_occurred_on,
      default_shelf_life_days: bulk_param(:default_shelf_life_days),
      rows: bulk_row_params
    ).call
    redirect_to production_path,
      notice: t("production.success_bulk", count: runs.size, numbers: runs.map(&:run_number).join(", "))
  rescue Inventory::BulkRunManufacturingService::Error, Inventory::RunManufacturingService::Error => e
    flash.now[:alert] = e.message
    load_manufacturing_bulk_sheet
    render :index, status: :unprocessable_entity
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
