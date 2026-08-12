# frozen_string_literal: true

module Admin
  module Inventory
    class ManufacturingTemplatesController < BaseController
      before_action :set_template, only: %i[show edit update destroy run]

      def index
        authorize_inventory_index!(ManufacturingTemplate)
        @templates = ManufacturingTemplate.includes(:output_ingredient, :manufacturing_template_lines).ordered
        @sortable = true
      end

      def reorder
        authorize_inventory!(:update)
        positions = params[:positions].presence || JSON.parse(request.body.read).fetch("positions")
        positions.each do |id, position|
          ManufacturingTemplate.where(id: id).update_all(position: position.to_i)
        end
        head :ok
      end

      def show
        authorize_inventory!(:show)
        @lines = @template.manufacturing_template_lines.includes(:ingredient)
        @recent_runs = @template.manufacturing_runs.includes(:user, :location).recent.limit(20)
        @production_locations = production_locations
        @default_production_location_id = @production_locations.find(&:central_kitchen?)&.id
      end

      def new
        @template = ManufacturingTemplate.new(active: false, yield_quantity: 1)
        authorize_inventory!(:create)
        load_form_data
        build_line_items
      end

      def create
        @template = ManufacturingTemplate.new(template_params)
        authorize_inventory!(:create)
        if @template.save
          redirect_to admin_inventory_manufacturing_template_path(@template),
            notice: t("flash.manufacturing_template.created")
        else
          load_form_data
          build_line_items
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize_inventory!(:update)
        load_form_data
        build_line_items
      end

      def update
        authorize_inventory!(:update)
        if @template.update(template_params)
          redirect_to admin_inventory_manufacturing_template_path(@template),
            notice: t("flash.manufacturing_template.updated")
        else
          load_form_data
          build_line_items
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_inventory!(:destroy)
        if @template.manufacturing_runs.exists?
          redirect_to admin_inventory_manufacturing_templates_path,
            alert: t("flash.manufacturing_template.cannot_delete_with_runs")
        else
          @template.destroy!
          redirect_to admin_inventory_manufacturing_templates_path,
            notice: t("flash.manufacturing_template.removed")
        end
      end

      def run
        authorize @template, :create?, policy_class: ProductionPolicy

        unless @template.active? && @template.manufacturing_template_lines.any?
          redirect_to admin_inventory_manufacturing_template_path(@template),
            alert: t("inventory.manufacturing.templates.cannot_run")
          return
        end

        location = production_locations.find { |l| l.id == params[:location_id] }
        if location.blank?
          redirect_to admin_inventory_manufacturing_template_path(@template),
            alert: t("production.location_required")
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

        redirect_to admin_inventory_manufacturing_template_path(@template),
          notice: t("production.success", number: run.run_number)
      rescue ::Inventory::RunManufacturingService::Error => e
        redirect_to admin_inventory_manufacturing_template_path(@template), alert: e.message
      end

      private

      def set_template
        @template = ManufacturingTemplate.find(params[:id])
        @manufacturing_template = @template
      end

      # Central kitchens first (the usual production site), then branches.
      def production_locations
        Location.active.central_kitchens.ordered.to_a + Location.active.branches.ordered.to_a
      end

      # The production date: defaults to today, never in the future (a run can be
      # backdated when it was recorded late, but not post-dated).
      def production_date(raw)
        date = (Date.parse(raw.to_s) rescue Date.current)
        [date, Date.current].min
      end

      def template_params
        params.require(:manufacturing_template).permit(
          :name, :output_ingredient_id, :yield_quantity, :yield_unit, :active, :position, :notes,
          :control_mode, :main_ingredient_id,
          manufacturing_template_lines_attributes: %i[id ingredient_id quantity_used unit _destroy]
        )
      end

      def load_form_data
        @ingredients = Ingredient.active.includes(:ingredient_units).order(:name)
        @ingredient_available_units = @ingredients.to_h do |i|
          [i.id, i.available_units.map { |u| [helpers.ingredient_unit_label(u), u] }]
        end
      end

      # Input lines are managed dynamically in the form (add/remove). Only seed a
      # single blank row when there are none, so the user always has one to fill.
      def build_line_items
        return if @template.manufacturing_template_lines.reject(&:marked_for_destruction?).any?

        @template.manufacturing_template_lines.build
      end
    end
  end
end
