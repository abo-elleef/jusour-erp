# frozen_string_literal: true

module Admin
  module Accounting
    # Money paid to staff in a month — the first report under the Staff
    # section of the reports hub. Authorized as payroll:view through
    # AccountingNav, the same as the payroll pages it summarises.
    #
    # Not paginated: one row per employee on payroll or paid that month, which
    # is bounded by the size of the staff list.
    class StaffPaymentsReportsController < BaseController
      include StaffLocationFilter

      def index
        @payroll_month = parse_payroll_month
        load_staff_location_filter
        @sort = params[:sort].presence_in(::Accounting::StaffPaymentsReportService::SORTABLE_COLUMNS) ||
                ::Accounting::StaffPaymentsReportService::DEFAULT_SORT
        @sort_direction = params[:direction] == "desc" ? "desc" : "asc"
        @report = ::Accounting::StaffPaymentsReportService.new(
          @payroll_month,
          users: apply_staff_location_filter(User.all),
          sort: @sort,
          direction: @sort_direction
        )
      end
    end
  end
end
