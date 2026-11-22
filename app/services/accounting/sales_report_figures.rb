# frozen_string_literal: true

module Accounting
  # Figures the Sales report's PDF and CSV both show that the report service
  # doesn't compute itself. One place, so the two exports can't disagree.
  module SalesReportFigures
    module_function

    # Every category with its units and money, built from the item rows so it
    # adds up to them (items with no category share one row). Highest net first.
    def category_summary(items, uncategorized:)
      items.group_by { |r| r[:category] || uncategorized }.map do |name, rows|
        {
          name: name,
          units_sold: rows.sum { |r| r[:units_sold] },
          revenue_cents: rows.sum { |r| r[:revenue_cents] },
          discount_cents: rows.sum { |r| r[:discount_cents] },
          net_cents: rows.sum { |r| r[:net_cents] }
        }
      end.sort_by { |g| [-g[:net_cents], g[:name].to_s] }
    end

    # Why collected money differs from net sales: payments also carry the
    # drivers' delivery fees, tips and tax. parts: [[key, cents], ...] with
    # net sales first; difference: whatever those don't explain.
    def reconciliation(summary, collected_cents)
      parts = [[:net_sales, summary[:net_sales_cents].to_i]]
      parts << [:delivery_fees, summary[:delivery_fee_cents].to_i] if summary[:delivery_fee_cents].to_i.positive?
      parts << [:tips, summary[:tip_cents].to_i] if summary[:tip_cents].to_i.positive?
      parts << [:tax, summary[:tax_cents].to_i] if summary[:tax_cents].to_i.positive?
      explained = parts.sum { |_, cents| cents }
      { parts: parts, explained_cents: explained, difference_cents: collected_cents - explained }
    end

    RECONCILIATION_LABELS = {
      net_sales: "accounting.sales_reports.net_sales",
      delivery_fees: "accounting.sales_reports.pdf.delivery_fees",
      tips: "accounting.sales_reports.pdf.tips",
      tax: "accounting.sales_reports.pdf.tax"
    }.freeze

    def reconciliation_label(key)
      I18n.t(RECONCILIATION_LABELS.fetch(key))
    end
  end
end
