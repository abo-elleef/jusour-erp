# frozen_string_literal: true

module Admin
  module Locations
    class IngredientsController < Admin::BaseController
      before_action :set_location
      before_action :set_ingredient_location, only: %i[update destroy]

      def index
        authorize @location, :show?, policy_class: LocationPolicy
        @all_ingredient_locations = @location.ingredient_locations
          .joins(:ingredient)
          .merge(Ingredient.active)
          .includes(ingredient: :ingredient_category)
          .order("ingredients.name ASC")

        @low_stock_count = @location.ingredient_locations.low_stock.count
        @out_of_stock_count = @location.ingredient_locations.out_of_stock.count
        @has_positive_stock = @location.ingredient_locations.where("quantity_on_hand > 0").exists?

        @stock_filter = params[:stock].presence
        @ingredient_locations = apply_stock_filter(@all_ingredient_locations)

        assigned_ids = @location.ingredient_locations.pluck(:ingredient_id)
        @available_ingredients = Ingredient.active
          .where.not(id: assigned_ids)
          .includes(:ingredient_category)
          .order(:name)

        load_balance_history_chart
      end

      def create
        authorize @location, :update?, policy_class: LocationPolicy
        ingredient = Ingredient.find(params[:ingredient_id])
        il = @location.ingredient_locations.find_or_initialize_by(ingredient: ingredient)
        if il.new_record?
          il.reorder_threshold = ingredient.reorder_threshold
          il.max_quantity = ingredient.max_quantity
        end
        il.quantity_on_hand = 0 if il.new_record?

        if il.save
          redirect_to admin_location_ingredients_path(@location),
            notice: t("flash.ingredient_location.assigned")
        else
          redirect_to admin_location_ingredients_path(@location),
            alert: il.errors.full_messages.to_sentence
        end
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
        # The delta may be entered in an alternate unit; store it in the base unit.
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

      def apply_stock_filter(scope)
        case @stock_filter
        when "low" then scope.low_stock
        when "out" then scope.out_of_stock
        else scope
        end
      end

      def ingredient_location_params
        params.require(:ingredient_location).permit(:reorder_threshold, :max_quantity)
      end

      def ensure_ingredient_assigned!(ingredient)
        @location.ingredient_locations.find_or_create_by!(ingredient: ingredient) do |il|
          il.reorder_threshold = ingredient.reorder_threshold
          il.max_quantity = ingredient.max_quantity
          il.quantity_on_hand = 0
        end
      end

      def load_balance_history_chart
        @chart_days = ::Inventory::LocationBalanceHistoryService::ALLOWED_DAYS.include?(params[:chart_days].to_i) ?
          params[:chart_days].to_i :
          ::Inventory::LocationBalanceHistoryService::DEFAULT_DAYS
        @chart_ingredient_ids = Array(params[:chart_ingredient_ids]).map(&:presence).compact.uniq
          .first(::Inventory::LocationBalanceHistoryService::MAX_INGREDIENTS)
        @balance_history = ::Inventory::LocationBalanceHistoryService.new(
          location: @location,
          ingredient_ids: @chart_ingredient_ids,
          days: @chart_days
        ).call
      end
    end
  end
end
