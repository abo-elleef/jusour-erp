# frozen_string_literal: true

module Public
  class MenusController < ApplicationController
    skip_before_action :authenticate_user!
    before_action :set_company
    before_action :set_locale_from_company
    before_action :set_location, only: :show

    layout "public_menu"

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
    end

    private

    def set_company
      @company = Company.find_by!(slug: params[:company_slug], active: true)
      Current.company = @company
    end

    def set_location
      @location = Location.publicly_accessible.find_by!(slug: params[:location_slug])
    end

    def set_locale_from_company
      return if session[:locale].present?

      locale = @company&.locale&.to_sym
      session[:locale] = locale.to_s if locale && I18n.available_locales.include?(locale)
    end
  end
end
