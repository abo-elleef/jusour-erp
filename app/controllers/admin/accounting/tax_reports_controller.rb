# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class TaxReportsController < BaseController
      def index
        parse_date_range
        completed_orders = Order.completed.where(created_at: BusinessDay.range_between(@start_date, @end_date))
        order_ids = completed_orders.pluck(:id)

        @tax_rows = TaxRate.active.map do |rate|
          taxable_revenue = OrderItem.joins(:order, :menu_item)
            .where(orders: { id: order_ids })
            .where(menu_items: { tax_category: rate.tax_category })
            .sum("order_items.quantity * order_items.unit_price_cents")
            .to_i

          tax_collected = (taxable_revenue * rate.rate).round

          {
            rate: rate,
            taxable_revenue_cents: taxable_revenue,
            tax_collected_cents: tax_collected
          }
        end

        @total_tax_cents = @tax_rows.sum { |r| r[:tax_collected_cents] }

        respond_to do |format|
          format.html
          format.csv { send_data generate_tax_csv, filename: "tax-report-#{@start_date}-#{@end_date}.csv" }
        end
      end

      private

      def generate_tax_csv
        CSV.generate(headers: true) do |csv|
          csv << %w[Tax\ Rate Tax\ Category Taxable\ Revenue Tax\ Collected]
          @tax_rows.each do |row|
            csv << [
              row[:rate].name,
              row[:rate].tax_category,
              format_money(row[:taxable_revenue_cents]),
              format_money(row[:tax_collected_cents])
            ]
          end
          csv << []
          csv << ["Total", "", "", format_money(@total_tax_cents)]
        end
      end
    end
  end
end
