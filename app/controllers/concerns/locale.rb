# frozen_string_literal: true

module Locale
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
  end

  private

  def switch_locale(&action)
    I18n.with_locale(resolve_locale, &action)
  end

  def resolve_locale
    requested = params[:locale].presence || session[:locale].presence
    requested = requested.to_sym if requested.present?

    if params[:locale].present? && I18n.available_locales.include?(requested)
      session[:locale] = requested.to_s
    end

    locale = session[:locale]&.to_sym
    locale = I18n.default_locale unless I18n.available_locales.include?(locale)
    locale
  end
end
