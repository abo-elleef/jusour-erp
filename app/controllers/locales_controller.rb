# frozen_string_literal: true

class LocalesController < ApplicationController
  skip_before_action :authenticate_user!

  def update
    locale = params[:locale].to_sym
    locale = I18n.default_locale unless I18n.available_locales.include?(locale)

    session[:locale] = locale.to_s
    redirect_back(fallback_location: root_path, status: :see_other)
  end
end
