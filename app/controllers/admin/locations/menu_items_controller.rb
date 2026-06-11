# frozen_string_literal: true

module Admin
  module Locations
    class MenuItemsController < Admin::BaseController
      before_action :set_location
      before_action :set_location_menu_item, only: %i[update]

      # GET /admin/locations/:location_id/menu_items
      # Shows all company menu items with their availability toggles for this location
      def index
        authorize @location, :show?, policy_class: LocationPolicy
        @categories = Category.active.includes(
          menu_items: { location_menu_items: nil }
        ).order(:position, :name)
        @location_menu_items_map = @location.location_menu_items
          .index_by(&:menu_item_id)
      end

      # PATCH /admin/locations/:location_id/menu_items/:id
      def update
        authorize @location, :update?, policy_class: LocationPolicy
        if @location_menu_item.update(location_menu_item_params)
          respond_to do |format|
            format.html { redirect_to admin_location_menu_items_path(@location), notice: t("flash.location_menu_item.updated") }
            format.json { render json: { success: true } }
            format.turbo_stream
          end
        else
          respond_to do |format|
            format.html { redirect_to admin_location_menu_items_path(@location), alert: @location_menu_item.errors.full_messages.to_sentence }
            format.json { render json: { errors: @location_menu_item.errors.full_messages }, status: :unprocessable_entity }
          end
        end
      end

      # POST /admin/locations/:location_id/menu_items/:id/toggle
      def toggle
        authorize @location, :update?, policy_class: LocationPolicy
        menu_item = MenuItem.find(params[:menu_item_id])
        lmi = @location.location_menu_items.find_or_initialize_by(menu_item: menu_item)
        lmi.available = !lmi.available?
        lmi.save!
        respond_to do |format|
          format.html { redirect_to admin_location_menu_items_path(@location) }
          format.turbo_stream
          format.json { render json: { available: lmi.available } }
        end
      end

      # POST /admin/locations/:location_id/menu_items/bulk_update
      def bulk_update
        authorize @location, :update?, policy_class: LocationPolicy
        item_ids = params[:menu_item_ids] || []
        available = params[:available] == "true"

        MenuItem.where(id: item_ids).find_each do |menu_item|
          lmi = @location.location_menu_items.find_or_initialize_by(menu_item: menu_item)
          lmi.available = available
          lmi.save!
        end

        redirect_to admin_location_menu_items_path(@location), notice: t("flash.location_menu_item.bulk_updated")
      end

      private

      def set_location
        @location = Location.find(params[:location_id])
      end

      def set_location_menu_item
        @location_menu_item = @location.location_menu_items.find_or_initialize_by(
          menu_item_id: params[:id]
        )
      end

      def location_menu_item_params
        permitted = params.require(:location_menu_item).permit(:available, :price_override_dollars)
        dollars = permitted.delete(:price_override_dollars)
        if dollars.present?
          permitted[:price_override_cents] = (BigDecimal(dollars.to_s) * 100).round
        end
        permitted
      end
    end
  end
end
