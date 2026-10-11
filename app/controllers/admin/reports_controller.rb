# frozen_string_literal: true

module Admin
  # Single landing page for every report in the app — inventory, accounting,
  # and (for distribution companies) sales — so a report is one click from the
  # sidebar instead of buried under whichever module happens to own it.
  class ReportsController < BaseController
    before_action :require_reports_access!

    def index
      @sections = view_context.reports_hub_sections
    end

    private

    def require_reports_access!
      return if view_context.reports_any_access?

      flash[:alert] = t("flash.access_denied")
      redirect_to admin_root_path
    end
  end
end
