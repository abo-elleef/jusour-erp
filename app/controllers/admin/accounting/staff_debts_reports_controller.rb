# frozen_string_literal: true

module Admin
  module Accounting
    # Staff who owe the company money, and what they have repaid this month.
    # Under the Staff section of the reports hub; authorized as payroll:view
    # through AccountingNav, like the payroll pages.
    #
    # Not paginated: one row per employee who owes, which is bounded by the
    # size of the staff list (a handful in practice).
    class StaffDebtsReportsController < BaseController
      include StaffLocationFilter

      def index
        @payroll_month = parse_payroll_month
        load_staff_location_filter
        @sort = params[:sort].presence_in(::Accounting::StaffDebtsReportService::SORTABLE_COLUMNS) ||
                ::Accounting::StaffDebtsReportService::DEFAULT_SORT
        @sort_direction = params[:direction].presence_in(%w[asc desc]) || (@sort == "name" ? "asc" : "desc")
        @report = ::Accounting::StaffDebtsReportService.new(
          @payroll_month,
          users: apply_staff_location_filter(User.all),
          sort: @sort,
          direction: @sort_direction
        )
      end
    end
  end
end
