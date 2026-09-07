# frozen_string_literal: true

module Admin
  module Sales
    # What the distributor sold, over a date range. Built on the sales documents
    # rather than on POS orders — a distributor has no tickets, which is why the
    # restaurant sales report reads empty for them.
    class ReportsController < BaseController
      include SessionDateRange

      def index
        parse_date_range(default_start: 30.days.ago.to_date)
        @report = ::Sales::SalesReportService.new(@start_date, @end_date).call
      end
    end
  end
end
