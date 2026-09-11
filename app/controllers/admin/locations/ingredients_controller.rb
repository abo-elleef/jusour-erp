# frozen_string_literal: true

module Admin
  module Locations
    class IngredientsController < Admin::BaseController
      before_action :set_location
      before_action :set_ingredient_location, only: %i[update destroy]

      def index
        authorize @location, :show?, policy_class: LocationPolicy

        @stock_filter = params[:stock].presence
        @search       = params[:search].to_s.strip

        # All active ingredients, left-joined to this location's stock rows so
        # every ingredient appears even if the branch has never tracked it.
        base = Ingredient.active
          .includes(:ingredient_category, :suppliers, :unit_ref, :ingredient_units,
                    ingredient_locations: nil)
          .left_joins(:ingredient_locations)
          .where("ingredient_locations.location_id = ? OR ingredient_locations.id IS NULL", @location.id)
          .select("ingredients.*, COALESCE((SELECT quantity_on_hand FROM ingredient_locations WHERE ingredient_id = ingredients.id AND location_id = '#{@location.id}' LIMIT 1), 0) AS branch_quantity")
          .order(:name)

        base = base.where("ingredients.name ILIKE :q OR ingredients.code ILIKE :q", q: "%#{@search}%") if @search.present?

        @ingredients = apply_branch_stock_filter(base)

        il_map = @location.ingredient_locations.index_by(&:ingredient_id)
        @ingredient_location_map = il_map

        @low_stock_count  = il_map.values.count { |il| il.stock_status == :low }
        @out_of_stock_count = il_map.values.count { |il| il.stock_status == :out }
        @total_tracked    = il_map.size

        @has_positive_stock = il_map.values.any? { |il| il.quantity_on_hand > 0 }

        @adjustment_types = StockAdjustment::ADJUSTMENT_TYPES
      end

      def update
        authorize @location, :update?, policy_class: LocationPolicy
        if @ingredient_location.update(ingredient_location_params)
          redirect_to admin_location_ingredients_path(@location),
            notice: t("flash.ingredient_location.updated")
        else
          redirect_to admin_location_ingredients_path(@location),
            alert: @ingredient_location.errors.full_messages.to_sentence
        end
      end

      def destroy
        authorize @location, :update?, policy_class: LocationPolicy
        @ingredient_location.destroy
        redirect_to admin_location_ingredients_path(@location),
          notice: t("flash.ingredient_location.removed")
      end

      def adjust
        authorize @location, :update?, policy_class: LocationPolicy
        ingredient = Ingredient.find(params[:id])
        ensure_ingredient_assigned!(ingredient)
        delta = ingredient.to_base(BigDecimal(params[:quantity_delta].to_s), params[:unit])

        StockAdjustment.create!(
          ingredient: ingredient,
          user: current_user,
          location: @location,
          quantity_delta: delta,
          unit: params[:unit].presence,
          adjustment_type: params[:adjustment_type],
          reason_notes: params[:reason_notes],
          maintain_batches: true
        )

        redirect_to admin_location_ingredients_path(@location),
          notice: t("flash.ingredient.adjusted")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_location_ingredients_path(@location),
          alert: e.record.errors.full_messages.to_sentence
      end

      def clear_stock
        authorize @location, :update?, policy_class: LocationPolicy

        if @location.central_kitchen?
          return render plain: t("inventory.clear_location_stock.errors.central_kitchen_not_allowed"),
                        status: :unprocessable_entity
        end

        result = ::Inventory::ClearLocationStockService.new(
          location: @location,
          user: current_user
        ).call

        redirect_to admin_location_ingredients_path(@location),
          notice: t("flash.ingredient_location.cleared", count: result.adjusted_count)
      rescue ::Inventory::ClearLocationStockService::Error => e
        redirect_to admin_location_ingredients_path(@location), alert: e.message
      end

      private

      def set_location
        @location = Location.find(params[:location_id])
      end

      def set_ingredient_location
        @ingredient_location = @location.ingredient_locations.find_by!(ingredient_id: params[:id])
      end

      def apply_branch_stock_filter(scope)
        case @stock_filter
        when "low"
          scope.where(
            "ingredients.id IN (SELECT ingredient_id FROM ingredient_locations WHERE location_id = ? AND quantity_on_hand > 0 AND reorder_threshold IS NOT NULL AND quantity_on_hand <= reorder_threshold)",
            @location.id
          )
        when "out"
          scope.where(
            "ingredients.id IN (SELECT ingredient_id FROM ingredient_locations WHERE location_id = ? AND quantity_on_hand <= 0)",
            @location.id
          )
        else
          scope
        end
      end

      def ingredient_location_params
        params.require(:ingredient_location).permit(:reorder_threshold, :max_quantity)
      end

      def ensure_ingredient_assigned!(ingredient)
        @location.ingredient_locations.find_or_create_by!(ingredient: ingredient) do |il|
          il.reorder_threshold = ingredient.reorder_threshold
          il.max_quantity      = ingredient.max_quantity
          il.quantity_on_hand  = 0
        end
      end
    end
  end
end
