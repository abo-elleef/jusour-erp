# frozen_string_literal: true

module Admin
  module Inventory
    class ManufacturingTemplatesController < BaseController
      before_action :set_template, only: %i[show edit update destroy]

      def index
        authorize_inventory_index!(ManufacturingTemplate)
        @templates = ManufacturingTemplate.includes(:output_ingredient, :manufacturing_template_lines).ordered
      end

      def show
        authorize_inventory!(:show)
        @lines = @template.manufacturing_template_lines.includes(:ingredient)
        @recent_runs = @template.manufacturing_runs.includes(:user).recent.limit(20)
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

      private

      def set_template
        @template = ManufacturingTemplate.find(params[:id])
        @manufacturing_template = @template
      end

      def template_params
        params.require(:manufacturing_template).permit(
          :name, :output_ingredient_id, :yield_quantity, :active, :position, :notes,
          manufacturing_template_lines_attributes: %i[id ingredient_id quantity_used _destroy]
        )
      end

      def load_form_data
        @ingredients = Ingredient.active.order(:name)
      end

      def build_line_items
        min_rows = @template.new_record? ? 5 : 3
        remaining = min_rows - @template.manufacturing_template_lines.reject(&:marked_for_destruction?).size
        remaining.times { @template.manufacturing_template_lines.build } if remaining.positive?
      end
    end
  end
end
