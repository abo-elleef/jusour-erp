# frozen_string_literal: true

module Admin
  module Accounting
    class ChartOfAccountsController < BaseController
      def index
        @start_date = params[:start_date]&.to_date || Date.current.beginning_of_year
        @end_date   = params[:end_date]&.to_date   || Date.current
        @coa = ::Accounting::ChartOfAccountsService.new(start_date: @start_date, end_date: @end_date)
      end
    end
  end
end
