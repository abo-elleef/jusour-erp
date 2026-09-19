# frozen_string_literal: true

module Admin
  module Inventory
    class UnitsController < BaseController
      before_action :set_unit, only: %i[edit update destroy]

      SORT_COLUMNS = %w[name].freeze

      def index
        authorize_inventory_index!(Unit)
        load_units
        @unit = Unit.new
      end

      def new
        authorize_inventory!(:manage_settings)
        @unit = Unit.new
      end

      def create
        authorize_inventory!(:manage_settings)
        @unit = Unit.new(unit_params)
        if @unit.save
          redirect_to admin_inventory_units_path, notice: t("flash.unit.created")
        else
          load_units
          render :index, status: :unprocessable_entity
        end
      end

      def edit
        authorize_inventory!(:manage_settings)
      end

      def update
        authorize_inventory!(:manage_settings)
        if @unit.update(unit_params)
          redirect_to admin_inventory_units_path, notice: t("flash.unit.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_inventory!(:manage_settings)
        if @unit.in_use?
          redirect_to admin_inventory_units_path,
            alert: t("flash.unit.cannot_delete_in_use", count: @unit.ingredients_using.count)
        else
          @unit.destroy
          redirect_to admin_inventory_units_path, notice: t("flash.unit.removed")
        end
      end

      private

      def set_unit
        @unit = Unit.find(params[:id])
      end

      def load_units
        @sort = SORT_COLUMNS.include?(params[:sort].to_s) ? params[:sort].to_s : nil
        @direction = params[:dir].to_s == "desc" ? "desc" : "asc"
        @units = if @sort == "name"
          Unit.order(Arel.sql("LOWER(units.name) #{@direction == "desc" ? "DESC" : "ASC"}"))
        else
          Unit.ordered
        end
      end

      def record_for_policy
        @unit || Ingredient.new
      end

      def unit_params
        # The `system` flag is seed provenance only and never user-settable.
        # Names are freely editable — references are by id, so a rename can't
        # orphan anything (built-in and custom units are treated identically).
        params.require(:unit).permit(:name, :active, :position)
      end
    end
  end
end
