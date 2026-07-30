# frozen_string_literal: true

module Admin
  module Inventory
    class StockTakesController < BaseController
      before_action :set_stock_take, only: %i[show update complete cancel]

      def index
        authorize_inventory_index!(StockTake)
        @total_count = StockTake.count
        @in_progress_count = StockTake.where(status: "in_progress").count
        @completed_count = StockTake.where(status: "completed").count
        @stock_takes = StockTake.includes(:user, :location, :stock_take_items).recent.limit(30)
        @stock_locations = Location.active.central_kitchens.ordered.to_a + Location.active.branches.ordered.to_a
        @locations_in_progress = StockTake.where(status: "in_progress").pluck(:location_id)
      end

      def show
        authorize_inventory!(:show)
        @items = @stock_take.stock_take_items
          .includes(ingredient: :ingredient_category)
          .joins(ingredient: :ingredient_category)
          .order("ingredient_categories.position ASC, ingredients.name ASC")
        @variance_count = @items.count { |i| i.variance.present? && !i.variance.to_d.zero? }
        @variance_value_cents = @items.sum { |i| i.variance_value_cents.to_i }
      end

      def create
        authorize_inventory!(:create)

        location = Location.find_by(id: params[:location_id])
        if location.blank?
          redirect_to admin_inventory_stock_takes_path, alert: t("inventory.stock_takes.index.location_required")
          return
        end
        if StockTake.where(location: location, status: "in_progress").exists?
          redirect_to admin_inventory_stock_takes_path, alert: t("inventory.stock_takes.index.already_in_progress")
          return
        end

        stock_take = StockTake.create!(
          user: current_user,
          location: location,
          status: "in_progress",
          started_at: count_started_at,
          notes: params[:notes]
        )
        # Seed one item per ingredient stocked at this location, with that
        # location's on-hand as the expected quantity (both in the base unit).
        IngredientLocation.where(location: location).includes(:ingredient).find_each do |il|
          next unless il.ingredient.active?

          stock_take.stock_take_items.create!(
            ingredient: il.ingredient,
            expected_quantity: il.quantity_on_hand
          )
        end
        redirect_to admin_inventory_stock_take_path(stock_take), notice: t("flash.stock_take.started")
      end

      def update
        authorize_inventory!(:update)
        params[:stock_take_items]&.each do |id, attrs|
          item = @stock_take.stock_take_items.find(id)
          item.counted_quantity = attrs[:counted_quantity]
          item.counted_unit = attrs[:counted_unit]
          item.calculate_variance!
          item.save!
        end
        redirect_to admin_inventory_stock_take_path(@stock_take), notice: t("flash.stock_take.saved")
      end

      def complete
        authorize_inventory!(:complete)
        params[:stock_take_items]&.each do |id, attrs|
          item = @stock_take.stock_take_items.find(id)
          item.counted_quantity = attrs[:counted_quantity] if attrs[:counted_quantity].present?
          item.counted_unit = attrs[:counted_unit] if attrs.key?(:counted_unit)
          item.calculate_variance!
          item.save!
        end

        @stock_take.stock_take_items.where(adjusted: false).find_each do |item|
          next if item.variance.to_d.zero?

          StockAdjustment.create!(
            ingredient: item.ingredient,
            user: current_user,
            location: @stock_take.location,
            quantity_delta: item.variance,
            adjustment_type: "cycle_count_correction",
            reason_notes: "Stock take ##{@stock_take.id}",
            maintain_batches: true
          )
          item.update!(adjusted: true)
        end

        @stock_take.update!(status: "completed", completed_at: Time.current)
        redirect_to admin_inventory_stock_takes_path, notice: t("flash.stock_take.completed")
      end

      def cancel
        authorize_inventory!(:complete)
        unless @stock_take.status == "in_progress"
          redirect_to admin_inventory_stock_take_path(@stock_take), alert: t("inventory.stock_takes.show.cancel_not_allowed")
          return
        end

        # Abandon the count: no variances are applied, so inventory is untouched.
        # The location is freed for a fresh take (the guard only blocks in_progress).
        @stock_take.update!(status: "cancelled")
        redirect_to admin_inventory_stock_takes_path, notice: t("flash.stock_take.cancelled")
      end

      private

      def set_stock_take
        @stock_take = StockTake.find(params[:id])
      end

      # Anchors the count to the user-entered date. A blank or future date falls
      # back to now; a past date keeps the current time-of-day for ordering.
      def count_started_at
        date = begin
          Date.parse(params[:count_date].to_s)
        rescue ArgumentError, TypeError
          nil
        end
        return Time.current if date.nil? || date >= Date.current

        date.to_time.change(hour: Time.current.hour, min: Time.current.min)
      end

      def record_for_policy
        @stock_take
      end
    end
  end
end
