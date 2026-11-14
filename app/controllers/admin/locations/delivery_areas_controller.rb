# frozen_string_literal: true

module Admin
  module Locations
    # The zones a branch delivers self-orders to, each with its own fee.
    class DeliveryAreasController < Admin::BaseController
      STATUSES = %w[active inactive].freeze

      before_action :set_location
      before_action :set_delivery_area, only: %i[edit update destroy]

      def index
        authorize DeliveryArea
        @sort = DeliveryArea::INDEX_SORTABLE_COLUMNS.include?(params[:sort].to_s) ? params[:sort].to_s : DeliveryArea::INDEX_DEFAULT_SORT
        @direction = params[:dir].to_s == "desc" ? "desc" : "asc"
        @search = params[:q].to_s.strip
        @status = STATUSES.include?(params[:status].to_s) ? params[:status].to_s : nil

        scope = @location.delivery_areas
        if @search.present?
          term = "%#{DeliveryArea.sanitize_sql_like(@search)}%"
          scope = scope.where("delivery_areas.name ILIKE :t OR delivery_areas.name_ar ILIKE :t", t: term)
        end
        scope = scope.where(active: @status == "active") if @status
        @filtered = @search.present? || @status.present?

        @pagy, @delivery_areas = pagy(:offset, scope.order(@sort => @direction, name: :asc, id: :asc), limit: 25)
      end

      def new
        @delivery_area = @location.delivery_areas.new(position: next_position)
        authorize @delivery_area
      end

      def create
        @delivery_area = @location.delivery_areas.new(delivery_area_params)
        authorize @delivery_area
        if @delivery_area.save
          redirect_to admin_location_delivery_areas_path(@location), notice: t("flash.delivery_area.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize @delivery_area
      end

      def update
        authorize @delivery_area
        if @delivery_area.update(delivery_area_params)
          redirect_to admin_location_delivery_areas_path(@location), notice: t("flash.delivery_area.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # Orders keep their own copy of the fee, so removing an area never changes
      # a past order. Deactivate instead to hide it while keeping it for later.
      def destroy
        authorize @delivery_area
        @delivery_area.destroy!
        redirect_to admin_location_delivery_areas_path(@location), notice: t("flash.delivery_area.removed")
      end

      private

      def set_location
        @location = Location.branches.find(params[:location_id])
      end

      def set_delivery_area
        @delivery_area = @location.delivery_areas.find(params[:id])
      end

      def next_position
        (@location.delivery_areas.maximum(:position) || 0) + 1
      end

      def delivery_area_params
        params.require(:delivery_area).permit(:name, :name_ar, :fee_pounds, :active, :position)
      end
    end
  end
end
