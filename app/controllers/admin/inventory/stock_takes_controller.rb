# frozen_string_literal: true

module Admin
  module Inventory
    class StockTakesController < BaseController
      before_action :set_stock_take, only: %i[show update complete]

      def index
        authorize_inventory_index!(StockTake)
        @total_count = StockTake.count
        @in_progress_count = StockTake.where(status: "in_progress").count
        @completed_count = StockTake.where(status: "completed").count
        @stock_takes = StockTake.includes(:user, :stock_take_items).recent.limit(30)
      end

      def show
        authorize_inventory!(:show)
        @items = @stock_take.stock_take_items
          .includes(ingredient: :ingredient_category)
          .joins(ingredient: :ingredient_category)
          .order("ingredient_categories.position ASC, ingredients.name ASC")
        @variance_count = @items.count { |i| i.variance.present? && !i.variance.to_d.zero? }
      end

      def create
        authorize_inventory!(:create)
        stock_take = StockTake.create!(
          user: current_user,
          status: "in_progress",
          started_at: Time.current,
          notes: params[:notes]
        )
        Ingredient.active.find_each do |ingredient|
          stock_take.stock_take_items.create!(
            ingredient: ingredient,
            expected_quantity: ingredient.quantity_on_hand
          )
        end
        redirect_to admin_inventory_stock_take_path(stock_take), notice: t("flash.stock_take.started")
      end

      def update
        authorize_inventory!(:update)
        params[:stock_take_items]&.each do |id, attrs|
          item = @stock_take.stock_take_items.find(id)
          item.counted_quantity = attrs[:counted_quantity]
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
          item.calculate_variance!
          item.save!
        end

        @stock_take.stock_take_items.where(adjusted: false).find_each do |item|
          next if item.variance.to_d.zero?

          StockAdjustment.create!(
            ingredient: item.ingredient,
            user: current_user,
            quantity_delta: item.variance,
            adjustment_type: "cycle_count_correction",
            reason_notes: "Stock take ##{@stock_take.id}"
          )
          item.update!(adjusted: true)
        end

        @stock_take.update!(status: "completed", completed_at: Time.current)
        redirect_to admin_inventory_stock_takes_path, notice: t("flash.stock_take.completed")
      end

      private

      def set_stock_take
        @stock_take = StockTake.find(params[:id])
      end

      def record_for_policy
        @stock_take
      end
    end
  end
end
