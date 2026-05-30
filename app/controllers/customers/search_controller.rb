# frozen_string_literal: true

module Customers
  class SearchController < ApplicationController
    def index
      @customers = Customer.ransack(
        name_or_email_or_phone_cont: params[:q]
      ).result.limit(10)
      render layout: false
    end
  end
end
