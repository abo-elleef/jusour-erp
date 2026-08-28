# frozen_string_literal: true

module Admin
  module Inventory
    class StockTakesController < BaseController
      SORT_COLUMNS = %w[category name counted expected expected_value counted_value].freeze

      before_action :set_stock_take, only: %i[show update complete cancel count_sheet]

      def index
        authorize_inventory_index!(StockTake)
        @total_count = StockTake.count
        @in_progress_count = StockTake.active.count
        @completed_count = StockTake.where(status: "completed").count
        @stock_takes = StockTake.includes(:user, :location, :supplier, :stock_take_items).recent.limit(30)
        @stock_locations = Location.active.central_kitchens.ordered.to_a + Location.active.branches.ordered.to_a
        @locations_in_progress = StockTake.active.pluck(:location_id)
        @suppliers = Supplier.active.order(:name)
      end

      def show
        authorize_inventory!(:show)
        @sort = SORT_COLUMNS.include?(params[:sort].to_s) ? params[:sort].to_s : "category"
        @direction = params[:dir].to_s == "desc" ? "desc" : "asc"
        @items = @stock_take.stock_take_items
          .includes(ingredient: [:ingredient_category, :ingredient_units])
          .joins(ingredient: :ingredient_category)
          .to_a
        @unit_costs = ::Inventory::LocationUnitCost.map_for(
          ingredients: @items.map(&:ingredient),
          location: @stock_take.location
        )
        @items = sort_items(@items)
        @variance_count = @items.count { |i| i.variance.present? && !i.variance.to_d.zero? }
        @variance_value_cents = @items.sum { |i| i.variance_value_cents(location_cost: @unit_costs[i.ingredient_id]).to_i }
        @counted_value_cents = @items.sum { |i| i.counted_value_cents(location_cost: @unit_costs[i.ingredient_id]).to_i }
      end

      # Printable blind count sheet for the take that is already open — the same
      # artifact the vendor and category pages produce, scoped to this take's own
      # items so what is written on paper matches what gets typed back in.
      def count_sheet
        authorize_inventory!(:show)
        @show_balance = params[:show_balance] == "1"
        @count_sheet_groups = ::Inventory::CountSheet.new(
          location: @stock_take.location,
          stock_take: @stock_take
        ).call
        @count_sheet_row_count = @count_sheet_groups.sum { |_, rows| rows.size }
      end

      def create
        authorize_inventory!(:create)

        location = Location.find_by(id: params[:location_id])
        if location.blank?
          redirect_to admin_inventory_stock_takes_path, alert: t("inventory.stock_takes.index.location_required")
          return
        end
        if StockTake.active.where(location: location).exists?
          redirect_to admin_inventory_stock_takes_path, alert: t("inventory.stock_takes.index.already_in_progress")
          return
        end

        supplier = Supplier.find_by(id: params[:supplier_id]) if params[:supplier_id].present?

        stock_take = StockTake.create!(
          user: current_user,
          location: location,
          supplier: supplier,
          status: "in_progress",
          started_at: count_started_at,
          notes: params[:notes]
        )
        items_count = seed_stock_take_items(stock_take, location, supplier: supplier)
        if items_count.zero?
          redirect_to admin_inventory_stock_take_path(stock_take),
            alert: t("inventory.stock_takes.index.no_items_for_filter")
        else
          redirect_to admin_inventory_stock_take_path(stock_take), notice: t("flash.stock_take.started")
        end
      end

      def update
        authorize_inventory!(:update)
        unless @stock_take.status == "in_progress"
          redirect_to stock_take_path_with_sort, alert: t("inventory.stock_takes.show.complete_not_allowed")
          return
        end

        params[:stock_take_items]&.each do |id, attrs|
          item = @stock_take.stock_take_items.find(id)
          item.counted_quantity = attrs[:counted_quantity]
          item.counted_unit = attrs[:counted_unit]
          item.calculate_variance!
          item.save!
        end
        redirect_to stock_take_path_with_sort, notice: t("flash.stock_take.saved")
      end

      def complete
        authorize_inventory!(:complete)
        unless @stock_take.completable?
          redirect_to stock_take_path_with_sort, alert: t("inventory.stock_takes.show.complete_not_allowed")
          return
        end

        params[:stock_take_items]&.each do |id, attrs|
          item = @stock_take.stock_take_items.find(id)
          item.counted_quantity = attrs[:counted_quantity] if attrs[:counted_quantity].present?
          item.counted_unit = attrs[:counted_unit] if attrs.key?(:counted_unit)
          item.calculate_variance!
          item.save!
        end

        @stock_take.update!(status: "completing")
        ::Inventory::CompleteStockTakeJob.perform_later(@stock_take.id, current_user.id)
        redirect_to admin_inventory_stock_takes_path, notice: t("flash.stock_take.completing")
      end

      def cancel
        authorize_inventory!(:complete)
        unless @stock_take.status == "in_progress"
          redirect_to stock_take_path_with_sort, alert: t("inventory.stock_takes.show.cancel_not_allowed")
          return
        end

        # Abandon the count: no variances are applied, so inventory is untouched.
        # The location is freed for a fresh take (the guard only blocks active takes).
        @stock_take.update!(status: "cancelled")
        redirect_to admin_inventory_stock_takes_path, notice: t("flash.stock_take.cancelled")
      end

      private

      def set_stock_take
        @stock_take = StockTake.find(params[:id])
      end

      def stock_take_path_with_sort
        opts = {}
        opts[:sort] = params[:sort] if SORT_COLUMNS.include?(params[:sort].to_s)
        opts[:dir] = params[:dir] if %w[asc desc].include?(params[:dir].to_s)
        admin_inventory_stock_take_path(@stock_take, opts)
      end

      def sort_items(items)
        present, blank = partition_for_sort(items)
        sorted_present = present.sort_by { |item| sort_key(item) }
        sorted_present.reverse! if @direction == "desc"
        sorted_present + blank
      end

      # Blank counted / counted_value rows stay at the bottom regardless of direction.
      def partition_for_sort(items)
        case @sort
        when "counted", "counted_value"
          items.partition { |item| item.counted_quantity.present? }
        else
          [items, []]
        end
      end

      def sort_key(item)
        cost = @unit_costs[item.ingredient_id]
        case @sort
        when "category"
          cat = item.ingredient.ingredient_category
          IngredientCategory.grouping_sort_key(cat) + [item.ingredient.name.to_s.downcase]
        when "counted"
          item.base_counted_quantity.to_d
        when "expected"
          item.expected_quantity.to_d
        when "expected_value"
          item.expected_value_cents(location_cost: cost).to_i
        when "counted_value"
          item.counted_value_cents(location_cost: cost).to_i
        else
          item.ingredient.name.to_s.downcase
        end
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

      # Seeds one line per active ingredient stocked at +location+. When +supplier+
      # is set, only ingredients linked to that supplier are included.
      def seed_stock_take_items(stock_take, location, supplier: nil)
        scope = IngredientLocation.where(location: location).includes(:ingredient)
        if supplier
          scope = scope.where(ingredient_id: supplier.ingredient_ids)
        end

        count = 0
        scope.find_each do |il|
          next unless il.ingredient.active?

          stock_take.stock_take_items.create!(
            ingredient: il.ingredient,
            expected_quantity: il.quantity_on_hand
          )
          count += 1
        end
        count
      end

      def record_for_policy
        @stock_take
      end
    end
  end
end
