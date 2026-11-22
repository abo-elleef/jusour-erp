# frozen_string_literal: true

require "prawn/table"

module Accounting
  # The Sales report as a PDF: the same numbers the page shows, laid out for
  # paper. It takes what the controller already prepared for the page (the
  # grouped or flat item list, the previous period, the hours), so the PDF
  # follows the page's view, category filter and sort and can't drift from it.
  #
  # Labels follow the interface language. Prawn draws characters left to right
  # as stored, so every Arabic string goes through #ar (joined letters,
  # right-to-left order) — the same step the receipt printer uses.
  class PdfReportService
    FONT_PATH = Rails.root.join("vendor/fonts/NotoNaskhArabic-Regular.ttf").to_s

    DARK = "111827"
    GRAY = "6B7280"
    LIGHT_GRAY = "9CA3AF"
    RED = "B91C1C"
    GREEN = "047857"
    AMBER = "D97706"
    CATEGORY_BG = "F3F4F6"
    HEADER_BG = "FEF3C7"
    BORDER = "E5E7EB"

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
      # modifiers: false drops the modifier choices under each item (the short PDF).
      @modifiers = modifiers
      # Labels and direction come from the language the report was asked in,
      # whenever #render / #item_rows are called.
      @locale = I18n.locale
    end

    def render
      I18n.with_locale(@locale) { build_document }
    end

    def item_rows
      I18n.with_locale(@locale) { build_item_rows }
    end

    private

    def build_document
      Prawn::Document.new(page_size: "A4", margin: [36, 36, 44, 36]) do |pdf|
        @pdf = pdf
        pdf.font_families.update("Noto" => { normal: FONT_PATH, bold: FONT_PATH })
        pdf.font "Noto"
        pdf.default_leading 1

        render_header
        render_summary
        render_payments
        render_categories
        render_items
        render_daily if multi_day?
        render_hourly
        render_footer
      end.render
    end

    # The rows of the category / item table as plain strings (before shaping),
    # one array per row with its kind first. Exposed (#item_rows) so specs can
    # check what the PDF lists without reading the PDF's glyph stream.
    def build_item_rows
      rows = []
      if grouped?
        @category_groups.each do |group|
          rows << [:category, group[:name], *figures(group, net_total)]
          group[:items].each { |item| rows.concat(item_and_choice_rows(item)) }
        end
      else
        @items.each { |item| rows.concat(item_and_choice_rows(item)) }
      end
      rows << [:total, t("total"), *(grouped? ? [] : [""]), *figures(totals_row, net_total)]
      rows
    end

    # ── Header ────────────────────────────────────────────────────────────

    def render_header
      @pdf.text ar(@company.name), size: 16, color: DARK, align: side if @company&.name.present?
      @pdf.text ar(t("pdf.title")), size: 20, color: DARK, align: side
      @pdf.text ar(range_label(@start, @end)), size: 11, color: GRAY, align: side
      @pdf.move_down 4
      @pdf.text ar(filters_line), size: 9, color: @include_open ? AMBER : GRAY, align: side
      @pdf.text ar(I18n.t("accounting.sales_reports.pdf.generated_at", time: I18n.l(Time.current, format: :short))),
        size: 8, color: LIGHT_GRAY, align: side
      @pdf.move_down 6
      @pdf.stroke_color AMBER
      @pdf.line_width 1.5
      @pdf.stroke_horizontal_rule
      @pdf.move_down 14
    end

    def filters_line
      parts = [@location ? "#{t('branch')}: #{@location.name}" : t("all_branches")]
      parts << (@include_open ? t("include_open") : t("pdf.completed_only"))
      parts << (grouped? ? t("view_grouped") : t("view_flat"))
      parts << "#{t('pdf.category')}: #{@item_category}" if @item_category
      parts << t("pdf.without_modifiers") unless @modifiers
      parts.join("  ·  ")
    end

    # ── Summary vs previous period ────────────────────────────────────────

    def render_summary
      s = @summary
      prev = @previous
      rows = [
        [t("gross_sales"), s[:gross_sales_cents], prev[:gross_sales_cents], :money],
        [t("discounts"), s[:discount_cents], prev[:discount_cents], :money_less]
      ]
      rows << [t("refunds"), s[:refunds_cents], prev[:refunds_cents], :money_less] if s[:refunds_cents].to_i.positive? || prev[:refunds_cents].to_i.positive?
      rows << [t("net_sales"), s[:net_sales_cents], prev[:net_sales_cents], :money_total]
      rows << [t("orders"), s[:order_count], prev[:order_count], :count]
      rows << [t("avg_ticket"), s[:average_ticket_cents], prev[:average_ticket_cents], :money]

      data = [[ar(""), ar(t("pdf.this_period")),
               ar(I18n.t("accounting.sales_reports.pdf.previous_period", range: range_label(@previous_start, @previous_end))),
               ar(t("pdf.change"))]]
      data += rows.map do |label, now, before, kind|
        fmt = kind == :count ? ->(v) { number(v) } : ->(v) { amount(v) }
        [ar(label), fmt.call(now), fmt.call(before), change(now, before, lower_is_better: kind == :money_less)]
      end

      section(t("pdf.summary"), data, column_widths: [150, 120, 150], numeric_from: 1) do |tbl|
        net_index = rows.index { |r| r[3] == :money_total } + 1
        tbl.row(net_index).background_color = CATEGORY_BG
        tbl.row(net_index).size = 10.5
        rows.each_with_index do |(_, _, _, kind), i|
          tbl.row(i + 1).column(col(1)).text_color = RED if kind == :money_less
        end
      end

      notes = []
      notes << I18n.t("accounting.sales_reports.promo_cost_line", amount: amount(s[:promo_cost_cents])) if s[:promo_cost_cents].to_i.positive?
      outside = []
      outside << I18n.t("accounting.sales_reports.tips_line", amount: amount(s[:tip_cents])) if s[:tip_cents].to_i.positive?
      outside << I18n.t("accounting.sales_reports.delivery_fees_line", amount: amount(s[:delivery_fee_cents])) if s[:delivery_fee_cents].to_i.positive?
      notes << "#{t('not_in_revenue')}: #{outside.join(' · ')}" if outside.any?
      if notes.any?
        @pdf.move_down 4
        notes.each { |line| @pdf.text ar(line), size: 8.5, color: GRAY, align: side }
      end
      @pdf.move_down 16
    end

    # Signed percentage change, coloured green when it moved the good way.
    def change(now, before, lower_is_better: false)
      return { content: "—", text_color: LIGHT_GRAY } if before.to_i.zero?

      pct = (now - before) * 100.0 / before.abs
      good = lower_is_better ? pct <= 0 : pct >= 0
      { content: format("%+.1f%%", pct), text_color: pct.zero? ? GRAY : (good ? GREEN : RED) }
    end

    # ── Payment methods ───────────────────────────────────────────────────

    def render_payments
      payments = @report[:by_payment_method].select { |_, c| c.positive? }.sort_by { |_, c| -c }
      if payments.empty?
        heading t("payment_methods")
        empty_line t("no_payments")
        return
      end

      total = payments.sum { |_, c| c }
      data = [[ar(t("method")), ar(t("pdf.amount")), ar(t("share"))]]
      data += payments.map do |method, cents|
        [ar(I18n.t("payment.methods.#{method}", default: method.to_s.humanize)), amount(cents), percent(cents, total)]
      end
      data << [ar(t("payments_total")), amount(total), "100%"]

      section(t("payment_methods"), data, column_widths: [200, 120, 80], numeric_from: 1, extra: 36) do |tbl|
        tbl.row(-1).background_color = CATEGORY_BG
      end
      reconciliation_line(total)
      @pdf.move_down 16
    end

    # Collected money is more than net sales: it also carries the drivers'
    # delivery fees, tips and tax. Spell the sum out so the gap doesn't read
    # as missing money; anything still unexplained is shown as is.
    def reconciliation_line(collected)
      return if collected == @summary[:net_sales_cents]

      rec = SalesReportFigures.reconciliation(@summary, collected)
      line = rec[:parts].map { |key, cents| "#{SalesReportFigures.reconciliation_label(key)} #{amount(cents)}" }.join(" + ")
      line += " = #{t('payments_total')} #{amount(rec[:explained_cents])}"
      diff = rec[:difference_cents]

      # One short line each: a wrapped Arabic line would come out bottom-up.
      @pdf.move_down 4
      @pdf.text ar(line), size: 8.5, color: GRAY, align: side
      @pdf.text ar("#{t('pdf.other_difference')} #{signed_amount(diff)}"), size: 8.5, color: AMBER, align: side unless diff.zero?
    end

    def signed_amount(cents)
      cents.negative? ? "-#{amount(-cents)}" : "+#{amount(cents)}"
    end

    # ── Category summary ──────────────────────────────────────────────────

    # Every category at a glance (units, net, share), whatever view or
    # filter the item table below is in. Built from the item rows so it adds
    # up to them.
    def render_categories
      groups = category_summary
      return if groups.empty?

      total = groups.sum { |g| g[:net_cents] }
      data = [[ar(t("pdf.category")), ar(t("pdf.units")), ar(t("net_revenue")), ar(t("share"))]]
      data += groups.map { |g| [ar(g[:name]), number(g[:units_sold]), amount(g[:net_cents]), percent(g[:net_cents], total)] }
      data << [ar(t("total")), number(groups.sum { |g| g[:units_sold] }), amount(total), "100%"]

      section(t("pdf.by_category"), data, column_widths: [200, 60, 110, 70], numeric_from: 1) do |tbl|
        tbl.row(-1).background_color = CATEGORY_BG
      end
      @pdf.move_down 16
    end

    def category_summary
      SalesReportFigures.category_summary(@report[:by_item], uncategorized: t("uncategorized"))
    end

    # ── Category / item / modifier table ──────────────────────────────────

    def render_items
      @pdf.start_new_page if @pdf.cursor < 90
      heading t("by_category_and_item")
      rows = item_rows
      if rows.size == 1
        empty_line t("no_sales")
        return
      end

      head = [t("category_item"), t("pdf.units"), t("revenue_before_discount"), t("promo_discount"), t("net_revenue"), t("share")]
      head.insert(1, t("pdf.category")) unless grouped?
      data = [head.map { |h| ar(h) }]
      styles = []

      rows.each do |kind, *cells|
        styles << [data.size, kind]
        data << cells.map { |c| ar(c.to_s) }
      end

      first_numeric = grouped? ? 1 : 2
      widths = [nil, 44, 72, 66, 72, 44]
      widths.insert(1, 90) unless grouped?
      widths[0] = @pdf.bounds.width - widths.compact.sum

      table(data, column_widths: widths, numeric_from: first_numeric, header: true) do |tbl|
        tbl.column(col(0)).overflow = :shrink_to_fit
        tbl.column(col(0)).min_font_size = 6
        tbl.column(col(0)).single_line = true
        styles.each { |index, kind| style_item_row(tbl.row(index), kind) }
      end
      @pdf.move_down 16
    end

    def style_item_row(row, kind)
      case kind
      when :category
        row.background_color = CATEGORY_BG
        row.size = 9.5
        row.text_color = DARK
      when :item
        row.columns(col(0)).padding = indent(3, 3, grouped? ? 16 : 6)
      when :group
        row.size = 7
        row.text_color = LIGHT_GRAY
        row.columns(col(0)).padding = indent(2, 1, grouped? ? 28 : 18)
        row.borders = [:left, :right]
      when :choice
        row.size = 7.5
        row.text_color = "4B5563"
        row.padding = [1, 6, 1, 6]
        row.columns(col(0)).padding = indent(1, 1, grouped? ? 38 : 28)
        row.borders = [:left, :right]
      when :total
        row.background_color = HEADER_BG
        row.size = 10
        row.text_color = DARK
      end
    end

    # An item, then each of its modifier groups and that group's choices.
    def item_and_choice_rows(item)
      category = grouped? ? [] : [item[:category] || t("uncategorized")]
      rows = [[:item, item[:name], *category, *figures(item, net_total)]]
      return rows unless @modifiers

      Array(item[:modifier_groups]).each do |group|
        rows << [:group, group[:name], *Array.new(category.size, ""), "", "", "", "", ""]
        group[:choices].each do |choice|
          rows << [:choice, choice[:name], *Array.new(category.size, ""), *choice_figures(choice)]
        end
      end
      rows
    end

    # Units, before discount, discount, net, share (blank when no base).
    def figures(row, base)
      [number(row[:units_sold]), amount(row[:revenue_cents]), discount_amount(row[:discount_cents]),
       amount(row[:net_cents]), base ? percent(row[:net_cents], base) : ""]
    end

    # A choice shows its units and net; before-discount and discount only when
    # a promo touched it — otherwise they just repeat the net and a dash.
    def choice_figures(choice)
      promo = choice[:discount_cents].to_i.nonzero?
      [number(choice[:units_sold]), promo ? amount(choice[:revenue_cents]) : "",
       promo ? discount_amount(choice[:discount_cents]) : "", amount(choice[:net_cents]), ""]
    end

    def totals_row
      rows = grouped? ? @category_groups : @items
      %i[units_sold revenue_cents discount_cents net_cents].to_h { |k| [k, rows.sum { |r| r[k].to_i }] }
    end

    def net_total
      @net_total ||= totals_row[:net_cents]
    end

    def grouped?
      @item_view == "grouped" && @category_groups
    end

    # ── By day / by hour ──────────────────────────────────────────────────

    def multi_day?
      @end > @start
    end

    def render_daily
      totals = @report[:daily_totals]
      counts = @report[:daily_order_counts]
      sum = totals.values.sum
      data = [[ar(t("day")), ar(t("orders")), ar(t("net_sales")), ar(t("share"))]]
      data += totals.map do |date, cents|
        [ar(I18n.l(date, format: "%a %d %b")), number(counts[date]), amount(cents), percent(cents, sum)]
      end
      data << [ar(t("total")), number(counts.values.sum), amount(sum), "100%"]
      section(t("pdf.by_day"), data, column_widths: [140, 70, 110, 70], numeric_from: 1) do |tbl|
        tbl.row(-1).background_color = CATEGORY_BG
      end
      @pdf.move_down 16
    end

    def render_hourly
      hours = @orders_by_hour.select { |h| h[:count].positive? }
      return if hours.empty?

      data = [[ar(t("hour")), ar(t("orders")), ar(t("net_sales")), ar(t("share"))]]
      data += hours.map do |h|
        [format("%02d:00", h[:hour]), number(h[:count]), amount(h[:sales_cents]), "#{h[:share_percent]}%"]
      end
      section(t("pdf.by_hour"), data, column_widths: [140, 70, 110, 70], numeric_from: 1)
    end

    # ── Footer ────────────────────────────────────────────────────────────

    # Drawn once every page exists, so each knows the page count.
    def render_footer
      total = @pdf.page_count
      label = ar("#{t('pdf.title')} · #{range_label(@start, @end)}")
      (1..total).each do |page|
        @pdf.go_to_page(page)
        # The footer sits in the bottom margin, outside the content box, so
        # draw it on the whole-page canvas.
        @pdf.canvas do
          at = [36, 32]
          width = @pdf.bounds.width - 72
          @pdf.text_box label, at: at, width: width, height: 24, align: side, size: 7.5, color: LIGHT_GRAY
          @pdf.text_box "#{page} / #{total}", at: at, width: width, height: 24, align: other_side, size: 7.5, color: LIGHT_GRAY
        end
      end
    end

    # ── Building blocks ───────────────────────────────────────────────────

    def heading(text)
      @pdf.text ar(text), size: 13, color: DARK, align: side
      @pdf.move_down 5
    end

    def empty_line(text)
      @pdf.text ar(text), size: 9, color: GRAY, align: side
      @pdf.move_down 16
    end

    # A table in the report's style: header row shaded, figures right-aligned
    # from column numeric_from on, header repeated on every page. In Arabic the
    # table is mirrored (names on the right); styling blocks name columns
    # through #col so they land on the right cells either way.
    def table(data, **opts, &block)
      build_table(data, **opts, &block).draw
    end

    # Heading + table kept on one page: when they don't fit in what's left of
    # this page but would fit on a fresh one, start a fresh one. A table longer
    # than a page (a month of days) just flows on. extra: room for a line
    # drawn right after the table.
    def section(title, data, extra: 0, **opts, &block)
      tbl = build_table(data, **opts, &block)
      needed = tbl.height + 30 + extra
      @pdf.start_new_page if needed > @pdf.cursor && needed < @pdf.bounds.height
      heading title
      tbl.draw
    end

    def build_table(data, column_widths:, numeric_from:, header: true, &block)
      # One width short: the last column takes the rest of the page.
      widths = column_widths.dup
      widths << (@pdf.bounds.width - widths.sum) if widths.size < data.first.size
      @cols = widths.size
      if rtl?
        data = data.map(&:reverse)
        widths = widths.reverse
      end

      @pdf.make_table(data, header: header, width: widths.sum, column_widths: widths, position: side,
        cell_style: { size: 8.5, padding: [3, 6], border_color: BORDER, border_width: 0.5, text_color: DARK }) do |tbl|
        (0...@cols).each do |i|
          column = tbl.column(col(i))
          column.align = i >= numeric_from ? :right : side
          next if i < numeric_from

          # Figures never wrap: a split number is unreadable.
          column.single_line = true
          column.overflow = :shrink_to_fit
          column.min_font_size = 6
        end
        tbl.row(0).background_color = HEADER_BG
        tbl.row(0).size = 8
        tbl.row(0).text_color = GRAY
        # A wrapped Arabic header would stack its words bottom-up; shrink instead.
        tbl.row(0).single_line = true
        tbl.row(0).overflow = :shrink_to_fit
        tbl.row(0).min_font_size = 6
        block&.call(tbl)
      end
    end

    # Index of logical column i in the drawn (possibly mirrored) table.
    def col(i)
      rtl? ? @cols - 1 - i : i
    end

    # Cell padding with the name indented from its reading side.
    def indent(top, bottom, size)
      rtl? ? [top, size, bottom, 6] : [top, 6, bottom, size]
    end

    def rtl?
      I18n.locale.to_s.start_with?("ar")
    end

    def side
      rtl? ? :right : :left
    end

    def other_side
      rtl? ? :left : :right
    end

    # Arabic uses numeric dates: each stays one left-to-right run once the
    # line is put in right-to-left order, so the two ends can't swap words.
    def range_label(from, to)
      fmt = rtl? ? "%d/%m/%Y" : :long
      from == to ? I18n.l(from, format: fmt) : "#{I18n.l(from, format: fmt)} – #{I18n.l(to, format: fmt)}"
    end

    def amount(cents)
      Money.new(cents || 0).format(symbol: false)
    end

    def discount_amount(cents)
      cents.to_i.zero? ? "—" : "-#{amount(cents)}"
    end

    def number(value)
      ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
    end

    def percent(part, whole)
      return "—" unless whole.to_i.positive?

      "#{(part.to_i * 100.0 / whole).round(1)}%"
    end

    def t(key)
      I18n.t("accounting.sales_reports.#{key}")
    end

    def ar(text)
      ::Printing::Escpos::Bidi.visual_for_print(text)
    end
  end
end
