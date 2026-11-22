# frozen_string_literal: true

require "csv"

module Accounting
  # The Sales report as a CSV: the same sections as the PDF, for a
  # spreadsheet. Each section is a title row, a header row and its rows, with
  # a blank row between sections.
  #
  # Spreadsheet-friendly on purpose: amounts are plain numbers (1234.50, no
  # currency, no thousands separator) and shares/changes are bare numbers
  # under a "%" header, so they sum and sort as numbers. Labels follow the
  # interface language; the file starts with a BOM so Excel reads the Arabic.
  #
  # Takes the same inputs as PdfReportService (the controller's page data),
  # so it follows the page's view, category filter and sort too.
  class SalesReportCsv
    BOM = "\uFEFF"

    def initialize(report:, start_date:, end_date:, previous:, previous_start:, previous_end:,
                   orders_by_hour:, item_view:, items:, category_groups: nil, item_category: nil,
                   location: nil, include_open: false, company: nil, modifiers: true)
      @report = report
      @summary = report[:summary]
      @start = start_date
      @end = end_date
      @previous = previous
      @previous_start = previous_start
      @previous_end = previous_end
      @orders_by_hour = orders_by_hour
      @item_view = item_view
      @items = items
      @category_groups = category_groups
      @item_category = item_category
      @location = location
      @include_open = include_open
      @company = company
      @modifiers = modifiers
      @locale = I18n.locale
    end

    def render
      I18n.with_locale(@locale) do
        BOM + CSV.generate do |csv|
          @csv = csv
          report_info
          summary
          payments
          categories
          items
          modifier_choices if @modifiers
          daily if @end > @start
          hourly
        end
      end
    end

    private

    def report_info
      section t("pdf.title")
      row t("pdf.company"), @company&.name
      row t("pdf.from"), @start.iso8601
      row t("pdf.to"), @end.iso8601
      row t("branch"), @location&.name || t("all_branches")
      row t("pdf.orders_counted"), @include_open ? t("include_open") : t("pdf.completed_only")
      row t("pdf.view"), grouped? ? t("view_grouped") : t("view_flat")
      row t("pdf.category"), @item_category if @item_category
      row t("pdf.generated"), I18n.l(Time.current, format: :short)
    end

    def summary
      section t("pdf.summary")
      row nil, t("pdf.this_period"), I18n.t("accounting.sales_reports.pdf.previous_period", range: "#{@previous_start.iso8601} – #{@previous_end.iso8601}"), "#{t('pdf.change')} %"
      s = @summary
      prev = @previous
      money_line t("gross_sales"), s[:gross_sales_cents], prev[:gross_sales_cents]
      money_line t("discounts"), s[:discount_cents], prev[:discount_cents]
      money_line t("promo_cost"), s[:promo_cost_cents], prev[:promo_cost_cents]
      money_line t("refunds"), s[:refunds_cents], prev[:refunds_cents]
      money_line t("net_sales"), s[:net_sales_cents], prev[:net_sales_cents]
      row t("orders"), s[:order_count].to_i, prev[:order_count].to_i, change(s[:order_count], prev[:order_count])
      money_line t("avg_ticket"), s[:average_ticket_cents], prev[:average_ticket_cents]
      money_line t("pdf.delivery_fees"), s[:delivery_fee_cents], prev[:delivery_fee_cents]
      money_line t("pdf.tips"), s[:tip_cents], prev[:tip_cents]
      money_line t("pdf.tax"), s[:tax_cents], prev[:tax_cents]
    end

    def payments
      section t("payment_methods")
      list = @report[:by_payment_method].select { |_, c| c.positive? }.sort_by { |_, c| -c }
      total = list.sum { |_, c| c }
      row t("method"), t("pdf.amount"), "#{t('share')} %"
      list.each do |method, cents|
        row I18n.t("payment.methods.#{method}", default: method.to_s.humanize), money(cents), share(cents, total)
      end
      row t("payments_total"), money(total), (total.positive? ? 100.0 : nil)

      # Why collected differs from net sales (delivery fees, tips, tax), as
      # rows that add up, then anything they don't explain.
      rec = SalesReportFigures.reconciliation(@summary, total)
      blank
      rec[:parts].each { |key, cents| row SalesReportFigures.reconciliation_label(key), money(cents) }
      row "= #{t('payments_total')}", money(rec[:explained_cents])
      row t("pdf.other_difference"), money(rec[:difference_cents])
    end

    def categories
      section t("pdf.by_category")
      groups = SalesReportFigures.category_summary(@report[:by_item], uncategorized: t("uncategorized"))
      net_total = groups.sum { |g| g[:net_cents] }
      row t("pdf.category"), *figure_headers
      groups.each { |g| row g[:name], *figures(g, net_total) }
      row t("total"), *figures(sum_rows(groups), net_total)
    end

    # The items in the page's order: under their categories in the grouped
    # view, the filtered/sorted list in the flat one.
    def items
      section t("by_category_and_item")
      list = grouped? ? @category_groups.flat_map { |g| g[:items] } : @items
      net_total = list.sum { |r| r[:net_cents] }
      row t("item"), t("pdf.category"), *figure_headers
      list.each { |r| row r[:name], r[:category] || t("uncategorized"), *figures(r, net_total) }
      row t("total"), nil, *figures(sum_rows(list), net_total)
    end

    # One row per item × modifier group × choice, so a pivot table can slice
    # them any way. A choice's money is the whole line it was sold on.
    def modifier_choices
      list = (grouped? ? @category_groups.flat_map { |g| g[:items] } : @items).select { |r| r[:modifier_groups].present? }
      return if list.empty?

      section t("pdf.modifier_choices")
      row t("item"), t("pdf.category"), t("modifier_group"), t("modifier_choice"), t("units_sold"),
          t("revenue_before_discount"), t("promo_discount"), t("net_revenue")
      list.each do |item|
        item[:modifier_groups].each do |group|
          group[:choices].each do |choice|
            row item[:name], item[:category] || t("uncategorized"), group[:name], choice[:name], choice[:units_sold].to_i,
                money(choice[:revenue_cents]), money(choice[:discount_cents]), money(choice[:net_cents])
          end
        end
      end
    end

    def daily
      section t("pdf.by_day")
      totals = @report[:daily_totals]
      counts = @report[:daily_order_counts]
      sum = totals.values.sum
      row t("day"), t("orders"), t("net_sales"), "#{t('share')} %"
      totals.each { |date, cents| row date.iso8601, counts[date].to_i, money(cents), share(cents, sum) }
      row t("total"), counts.values.sum, money(sum), (sum.positive? ? 100.0 : nil)
    end

    def hourly
      section t("pdf.by_hour")
      row t("hour"), t("orders"), t("net_sales"), "#{t('share')} %"
      @orders_by_hour.select { |h| h[:count].positive? }.each do |h|
        row format("%02d:00", h[:hour]), h[:count], money(h[:sales_cents]), h[:share_percent]
      end
    end

    # ── Building blocks ───────────────────────────────────────────────────

    def figure_headers
      [t("units_sold"), t("revenue_before_discount"), t("promo_discount"), t("net_revenue"), "#{t('share')} %"]
    end

    def figures(r, net_total)
      [r[:units_sold].to_i, money(r[:revenue_cents]), money(r[:discount_cents]), money(r[:net_cents]), share(r[:net_cents], net_total)]
    end

    def sum_rows(rows)
      %i[units_sold revenue_cents discount_cents net_cents].to_h { |k| [k, rows.sum { |r| r[k].to_i }] }
    end

    def money_line(label, now, before)
      row label, money(now), money(before), change(now, before)
    end

    def grouped?
      @item_view == "grouped" && @category_groups
    end

    def section(title)
      blank unless @csv.string.empty?
      row title
    end

    def row(*cells)
      @csv << cells
    end

    def blank
      @csv << []
    end

    def money(cents)
      format("%.2f", cents.to_i / 100.0)
    end

    def share(part, whole)
      whole.to_i.positive? ? (part.to_i * 100.0 / whole).round(1) : nil
    end

    # Blank when there's nothing to compare with (a % of zero means nothing).
    def change(now, before)
      before.to_i.zero? ? nil : ((now.to_i - before.to_i) * 100.0 / before.to_i.abs).round(1)
    end

    def t(key)
      I18n.t("accounting.sales_reports.#{key}")
    end
  end
end
