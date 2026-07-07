# frozen_string_literal: true

module Admin
  module Inventory
    class UnitsController < BaseController
      before_action :set_unit, only: %i[edit update destroy]

      def index
        authorize_inventory_index!(Unit)
        @units = Unit.ordered
        @unit = Unit.new
      end

      def new
        authorize_inventory!(:create)
        @unit = Unit.new
      end

      def create
        authorize_inventory!(:create)
        @unit = Unit.new(unit_params)
        if @unit.save
          redirect_to admin_inventory_units_path, notice: t("flash.unit.created")
        else
          @units = Unit.ordered
          render :index, status: :unprocessable_entity
        end
      end

      def edit
        authorize_inventory!(:update)
      end

      def update
        authorize_inventory!(:update)
        if @unit.update(unit_params)
          redirect_to admin_inventory_units_path, notice: t("flash.unit.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_inventory!(:destroy)
        if @unit.deletable?
          @unit.destroy
          redirect_to admin_inventory_units_path, notice: t("flash.unit.removed")
        else
          redirect_to admin_inventory_units_path, alert: t("flash.unit.cannot_delete_system")
        end
      end

      private

      def set_unit
        @unit = Unit.find(params[:id])
      end

      def record_for_policy
        @unit || Ingredient.new
      end

      def unit_params
        # System flag is never user-settable. Built-in unit names are locked so
        # existing ingredient/recipe unit values keep matching.
        permitted = params.require(:unit).permit(:name, :active, :position)
        permitted.delete(:name) if @unit&.system?
        permitted
      end
    end
  end
end
