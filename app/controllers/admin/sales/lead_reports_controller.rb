# frozen_string_literal: true

module Admin
  module Sales
    # Funnel, drop-off, and rep-performance reporting on the lead pipeline — split
    # out from the general sales reports page since it isn't about sales
    # documents at all. Gated on `leads:reports` specifically (narrower than
    # `leads:view`/`leads:manage`, which only cover the pipeline itself), so a
    # rep can work leads without necessarily seeing the performance leaderboard.
    #
    # All three tabs are cheap aggregate queries (COUNT/GROUP, not raw row
    # dumps), so unlike the general sales reports page they're computed eagerly
    # and switched client-side rather than lazy-loaded per tab.
    class LeadReportsController < Admin::BaseController
      include SessionDateRange

      before_action { require_feature!(:leads) }
      before_action :require_leads_reports

      def index
        parse_date_range(default_start: 30.days.ago.to_date)
        @service = ::Sales::LeadsReportService.new(@start_date, @end_date)
      end

      private

      def require_leads_reports
        return if current_user.can?("leads:reports")

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_sales_leads_path
      end
    end
  end
end
