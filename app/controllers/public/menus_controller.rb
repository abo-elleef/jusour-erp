# frozen_string_literal: true

module Public
  class MenusController < ApplicationController
    include PublicMenuScoped

    before_action :set_location, only: :show

    def index
      @locations = Location.publicly_accessible.ordered
      redirect_to public_menu_path(company_slug: @company.slug, location_slug: @locations.first.slug) if @locations.one?
    end

    def show
      menu = Menus::ForLocation.call(location: @location)
      @categories = menu.categories
      @menu_items = menu.menu_items
      @combos = menu.combos
      @promos_by_item_id = menu.promos_by_item_id
      @accepting_orders = @location.accepting_online_orders?
      @delivery_areas = @location.delivery_areas.active.ordered if @accepting_orders
    end
  end
end
