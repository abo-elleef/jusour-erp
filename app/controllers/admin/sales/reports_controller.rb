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

      def index
        parse_date_range(default_start: 30.days.ago.to_date)
        @customer_type = params[:customer_type] if Customer::CUSTOMER_TYPES.include?(params[:customer_type])
        @service = ::Sales::SalesReportService.new(@start_date, @end_date, customer_type: @customer_type)

        if SECTIONS.include?(params[:section])
          render_section(params[:section])
        else
          @summary = @service.summary
          @show_payment_method = @service.payment_method_variety > 1
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
    end
  end
end
