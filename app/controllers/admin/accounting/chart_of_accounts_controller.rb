# frozen_string_literal: true

module Admin
  module Accounting
    class ChartOfAccountsController < BaseController
      def index
        parse_date_range(default_start: Date.current.beginning_of_year)
        @coa = ::Accounting::ChartOfAccountsService.new(start_date: @start_date, end_date: @end_date)
      end
    end
  end
end
