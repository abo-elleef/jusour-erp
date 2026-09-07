# frozen_string_literal: true

module Admin
  module Accounting
    class FoodCostsController < BaseController
      before_action { require_feature!(:menu) }

      def index
        parse_date_range
        @food_cost = ::Accounting::FoodCostService.new(@start_date, @end_date).call
      end
    end
  end
end
