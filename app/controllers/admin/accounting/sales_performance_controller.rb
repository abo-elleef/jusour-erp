# frozen_string_literal: true

module Admin
  module Accounting
    # Sales by branch and order type, by cashier, and the voids/refunds behind
    # them. One page, three tabs: each is cheap (aggregated in the database), and
    # keeping them together lets an owner jump from "this cashier voided a lot"
    # to the actual voids with the same date range and branch filter.
    class SalesPerformanceController < BaseController
      before_action { require_feature!(:menu) }

      TABS = %w[branch cashier exceptions].freeze

      def index
        parse_date_range(default_start: Date.current.beginning_of_week(:saturday))

        @tab = TABS.include?(params[:tab]) ? params[:tab] : "branch"
        @locations = Location.order(:name)
        @location_id = params[:location_id].presence if @locations.exists?(id: params[:location_id])
        @sort = params[:sort].to_s
        @direction = params[:dir] == "asc" ? "asc" : "desc"
        @service = ::Accounting::SalesPerformanceService.new(@start_date, @end_date, location_id: @location_id)

        case @tab
        when "branch"
          @rows, @totals = @service.by_branch(sort: @sort, direction: @direction)
        when "cashier"
          @rows = @service.by_cashier(sort: @sort, direction: @direction)
        else
          @kind = params[:kind] if ::Accounting::SalesPerformanceService::EXCEPTION_KINDS.include?(params[:kind])
          @summary = @service.exceptions_summary
          @pagy, @events = pagy(:offset, @service.exceptions(kind: @kind, sort: @sort, direction: @direction), limit: 50)
        end
      end
    end
  end
end
