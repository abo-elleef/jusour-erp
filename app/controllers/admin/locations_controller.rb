# frozen_string_literal: true

module Admin
  class LocationsController < BaseController
    before_action :set_location, only: %i[show edit update destroy]

    def index
      @locations = policy_scope(Location).includes(:ingredient_locations, :location_menu_items).ordered
      authorize Location
    end

    def show
      authorize @location
      @ingredient_locations = @location.ingredient_locations
        .includes(ingredient: :ingredient_category)
        .joins(ingredient: :ingredient_category)
        .order("ingredient_categories.position ASC, ingredients.name ASC")
      @location_menu_items = @location.location_menu_items
        .includes(menu_item: :category)
        .joins(menu_item: :category)
        .order("categories.position ASC, menu_items.position ASC, menu_items.name ASC")
      @menu_items_count = @location_menu_items.count
      @available_count = @location_menu_items.available.count
    end

    def new
      @location = Location.new
      authorize @location
    end

    def create
      @location = Location.new(location_params)
      authorize @location
      if @location.save
        redirect_to admin_location_path(@location), notice: t("flash.location.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @location
    end

    def update
      authorize @location
      if @location.update(location_params)
        redirect_to admin_location_path(@location), notice: t("flash.location.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @location
      if @location.destroy
        redirect_to admin_locations_path, notice: t("flash.location.removed")
      else
        redirect_to admin_location_path(@location), alert: @location.errors.full_messages.to_sentence
      end
    end

    private

    def set_location
      @location = Location.find(params[:id])
    end

    def location_params
      params.require(:location).permit(:name, :slug, :location_type, :address, :phone, :whatsapp_number, :active, :position, :public_menu_enabled)
    end
  end
end
