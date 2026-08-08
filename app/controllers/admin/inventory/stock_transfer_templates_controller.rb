# frozen_string_literal: true

module Admin
  module Inventory
    class StockTransferTemplatesController < BaseController
      before_action :set_template, only: %i[show edit update destroy duplicate]

      def index
        authorize_inventory_index!(StockTransferTemplate)
        @templates = StockTransferTemplate.includes(:stock_transfer_template_lines).ordered
      end

      def show
        authorize_inventory!(:show)
        @lines = @template.stock_transfer_template_lines.includes(ingredient: :ingredient_category).ordered
      end

      def new
        @template = StockTransferTemplate.new(active: true)
        authorize_inventory!(:create)
        load_form_data
        build_line_items
      end

      def create
        @template = StockTransferTemplate.new(template_params)
        authorize_inventory!(:create)
        if @template.save
          redirect_to admin_inventory_stock_transfer_template_path(@template),
            notice: t("flash.stock_transfer_template.created")
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
          redirect_to admin_inventory_stock_transfer_template_path(@template),
            notice: t("flash.stock_transfer_template.updated")
        else
          load_form_data
          build_line_items
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_inventory!(:destroy)
        @template.destroy!
        redirect_to admin_inventory_stock_transfer_templates_path,
          notice: t("flash.stock_transfer_template.removed")
      end

      def duplicate
        authorize_inventory!(:create)
        copy = @template.duplicate
        if copy.save
          redirect_to edit_admin_inventory_stock_transfer_template_path(copy),
            notice: t("flash.stock_transfer_template.duplicated")
        else
          redirect_to admin_inventory_stock_transfer_template_path(@template),
            alert: copy.errors.full_messages.to_sentence
        end
      end

      private

      def set_template
        @template = StockTransferTemplate.find(params[:id])
      end

      def template_params
        params.require(:stock_transfer_template).permit(
          :name, :active, :position, :notes,
          :default_from_location_id, :default_to_location_id,
          stock_transfer_template_lines_attributes: %i[
            id ingredient_id default_quantity unit position _destroy
          ]
        )
      end

      def load_form_data
        @locations = Location.active.ordered
        @ingredients = Ingredient.active.includes(:ingredient_category, :ingredient_units).order(:name)
        @ingredient_available_units = @ingredients.to_h do |i|
          [i.id, i.available_units.map { |u| [helpers.ingredient_unit_label(u), u] }]
        end
        ActiveRecord::Associations::Preloader.new(
          records: @template.stock_transfer_template_lines.select(&:ingredient_id),
          associations: { ingredient: :ingredient_category }
        ).call
      end

      def build_line_items
        return if @template.stock_transfer_template_lines.reject(&:marked_for_destruction?).any?

        @template.stock_transfer_template_lines.build
      end

      def record_for_policy
        @template || super
      end
    end
  end
end
