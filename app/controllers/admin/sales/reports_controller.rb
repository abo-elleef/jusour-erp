# frozen_string_literal: true

module Admin
  module Sales
    # What the distributor sold, over a date range. Built on the sales documents
    # rather than on POS orders — a distributor has no tickets, which is why the
    # restaurant sales report reads empty for them.
    #
    # Each tab's table (by product, by customer, ...) is its own lazy-loaded Turbo
    # Frame (see index.html.erb) rather than computed up front — by_product and
    # by_customer alone can run into thousands of rows, so pulling every
    # breakdown on every page load (most of it never even looked at) doesn't
    # scale. Only the summary tiles and the tab bar are computed eagerly, both
    # cheap regardless of how large the underlying data gets.
    class ReportsController < BaseController
      include SessionDateRange

      SECTIONS = %w[product customer salesperson payment_method daily].freeze
      LEAD_SECTIONS = %w[leads_funnel leads_drop_reasons leads_performance].freeze

      before_action :require_leads_reports_access, if: -> { LEAD_SECTIONS.include?(params[:section]) }

      def index
        parse_date_range(default_start: 30.days.ago.to_date)

        if LEAD_SECTIONS.include?(params[:section])
          @leads_service = ::Sales::LeadsReportService.new(@start_date, @end_date)
          render_lead_section(params[:section])
          return
        end

        @customer_type = params[:customer_type] if Customer::CUSTOMER_TYPES.include?(params[:customer_type])
        @service = ::Sales::SalesReportService.new(@start_date, @end_date, customer_type: @customer_type)

        if SECTIONS.include?(params[:section])
          render_section(params[:section])
        else
          @summary = @service.summary
          @show_payment_method = @service.payment_method_variety > 1
          @show_leads = Current.company.feature_enabled?(:leads) && current_user.can?("leads:reports")
          @any_leads = @show_leads && Lead.exists?
        end
      end

      private

      def render_section(section)
        case section
        when "product"       then render partial: "product_section", locals: { rows: @service.by_product }
        when "customer"      then render partial: "customer_section", locals: { rows: @service.by_customer }
        when "salesperson"   then render partial: "salesperson_section", locals: { rows: @service.by_salesperson }
        when "payment_method" then render partial: "payment_method_section", locals: { rows: @service.by_payment_method }
        when "daily"         then render partial: "daily_section", locals: { rows: @service.daily }
        end
      end

      def render_lead_section(section)
        case section
        when "leads_funnel"
          render partial: "leads_funnel_section", locals: {
            rows: @leads_service.funnel, conversion_rate: @leads_service.conversion_rate,
            average_days_to_convert: @leads_service.average_days_to_convert,
            total_created: @leads_service.total_created, trend: @leads_service.trend
          }
        when "leads_drop_reasons"
          render partial: "leads_drop_reasons_section", locals: { rows: @leads_service.drop_reasons }
        when "leads_performance"
          render partial: "leads_performance_section", locals: { rows: @leads_service.by_performance }
        end
      end

      def require_leads_reports_access
        return if Current.company.feature_enabled?(:leads) && current_user.can?("leads:reports")

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_sales_reports_path
      end
    end
  end
end
