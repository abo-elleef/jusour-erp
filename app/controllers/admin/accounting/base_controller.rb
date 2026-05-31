# frozen_string_literal: true

module Admin
  module Accounting
    class BaseController < Admin::BaseController
      before_action :authorize_accounting!

      private

      def authorize_accounting!
        authorize :accounting, :index?
      end

      def parse_date_range
        @start_date = params[:start_date]&.to_date || 7.days.ago.to_date
        @end_date = params[:end_date]&.to_date || Date.current
      end
    end
  end
end
