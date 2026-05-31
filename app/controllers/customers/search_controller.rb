# frozen_string_literal: true

module Customers
  class SearchController < ApplicationController
    before_action :require_pos_access!

    def index
      @customers = if params[:q].to_s.strip.length >= 2
                     Customer.ransack(name_or_email_or_phone_or_phone_secondary_cont: params[:q].strip)
                             .result.order(:name, :phone)
                             .limit(10)
                   else
                     Customer.none
                   end
      render layout: false
    end

    private

    def require_pos_access!
      return if current_user&.cashier? || current_user&.admin_access?

      head :forbidden
    end
  end
end
