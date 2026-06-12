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

    ::Inventory::RunManufacturingService.new(
      template: @template,
      user: current_user,
      runs_count: runs_count,
      shelf_life_days: shelf_life_days,
      notes: params[:notes].presence
    ).call

    output_qty = runs_count * @template.yield_quantity.to_d
    expires_on = Date.current + shelf_life_days.days
    redirect_to production_path,
      notice: t(
        "production.success",
        runs: runs_count,
        template: @template.name,
        output: @template.output_ingredient.name,
        output_qty: output_qty,
        output_unit: helpers.ingredient_unit_label(@template.output_ingredient.unit),
        expires_on: l(expires_on, format: :short)
      )
  rescue Inventory::RunManufacturingService::Error => e
    redirect_to production_path, alert: e.message
  end

  private

  def require_production_access!
    return if current_user&.can_access_production?

    flash[:alert] = t("flash.production_access")
    redirect_to root_path
  end
end
