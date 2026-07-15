# frozen_string_literal: true

module Admin
  module Accounting
    class ChartOfAccountsController < BaseController
      def index
        @coa = ::Accounting::ChartOfAccountsService.new
      end
    end
  end
end
