# frozen_string_literal: true

# Shared by the public menu pages: anonymous, tenant picked from the URL slug.
module PublicMenuScoped
  extend ActiveSupport::Concern

  included do
    skip_before_action :authenticate_user!
    before_action :set_company
    before_action :set_locale_from_company
    layout "public_menu"
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
