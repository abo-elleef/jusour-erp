# frozen_string_literal: true

require "prawn/table"

module Accounting
  class PdfReportService
    def initialize(report, start_date, end_date)
      @report = report
      @start = start_date
      @end = end_date
    end

    def render
      Prawn::Document.new(page_size: "LETTER", margin: [36, 36, 36, 36]) do |pdf|
        pdf.text "Sales Report", size: 20, style: :bold
        pdf.text "#{@start.strftime('%B %d, %Y')} – #{@end.strftime('%B %d, %Y')}", size: 12, color: "555555"
        pdf.move_down 12

        pdf.text "Summary", size: 14, style: :bold
        pdf.move_down 6
        summary = @report[:summary]
        summary_data = [
          ["Gross Sales", format_money(summary[:gross_sales_cents])],
          ["Discounts", format_money(summary[:discount_cents])],
          ["Tax", format_money(summary[:tax_cents])],
          ["Tips", format_money(summary[:tip_cents])],
          ["Net Sales", format_money(summary[:net_sales_cents])],
          ["Order Count", summary[:order_count].to_s],
          ["Avg Ticket", format_money(summary[:average_ticket_cents])]
        ]
        pdf.table(summary_data, width: pdf.bounds.width,
          cell_style: { size: 10, padding: [4, 8] },
          column_widths: [200, 200])

        pdf.move_down 16
        pdf.text "Revenue by Category", size: 14, style: :bold
        pdf.move_down 6
        cat_data = [["Category", "Revenue"]] +
          @report[:by_category].map { |r| [r[:category], format_money(r[:revenue_cents])] }
        pdf.table(cat_data, width: pdf.bounds.width,
          header: true,
          cell_style: { size: 10, padding: [4, 8] },
          row_colors: %w[FFFFFF F4F4F4])
      end.render
    end

    private

    def format_money(cents)
      Money.new(cents || 0).format
    end
  end
end
