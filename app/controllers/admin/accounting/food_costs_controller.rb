# frozen_string_literal: true

module Admin
  module Accounting
    class FoodCostsController < BaseController
      def index
        parse_date_range
        @food_cost = ::Accounting::FoodCostService.new(@start_date, @end_date).call
      end
    end
  end
end
