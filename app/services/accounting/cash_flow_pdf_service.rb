# frozen_string_literal: true

require "prawn/table"

module Accounting
  class CashFlowPdfService
    AMBER = "D97706"
    GRAY  = "6B7280"
    DARK  = "111827"
    GREEN = "065F46"
    RED   = "991B1B"

    def initialize(cf, start_date, end_date, company)
      @cf      = cf
      @start   = start_date
      @end     = end_date
      @company = company
    end

    def render
      Prawn::Document.new(page_size: "A4", margin: [40, 50, 40, 50]) do |pdf|
        @pdf = pdf

        font_path = Rails.root.join("vendor/fonts/NotoNaskhArabic-Regular.ttf").to_s
        pdf.font_families.update("Noto" => { normal: font_path, bold: font_path })
        pdf.font "Noto"

        render_header
        pdf.move_down 20

        render_section(@cf.operating,  I18n.t("accounting.cash_flow.operating_activities"))
        pdf.move_down 12
        render_section(@cf.investing,  I18n.t("accounting.cash_flow.investing_activities"))
        pdf.move_down 12
        render_section(@cf.financing,  I18n.t("accounting.cash_flow.financing_activities"))
        pdf.move_down 20

        render_net_summary

        pdf.number_pages "<page> / <total>",
          at: [pdf.bounds.left, 0], align: :right, size: 8, color: GRAY
      end.render
    end

    private

    def render_header
      @pdf.text @company.name,
                size: 18, style: :bold, color: DARK
      @pdf.text I18n.t("accounting.cash_flow.title"),
                size: 13, color: GRAY
      @pdf.text "#{I18n.l(@start, format: :long)} – #{I18n.l(@end, format: :long)}",
                size: 10, color: GRAY
      @pdf.move_down 4
      @pdf.stroke_color AMBER
      @pdf.stroke_horizontal_rule
    end

    def render_section(section, heading)
      @pdf.fill_color "F9FAFB"
      @pdf.fill_rectangle [@pdf.bounds.left, @pdf.cursor], @pdf.bounds.width, 18
      @pdf.fill_color DARK
      @pdf.text_box heading,
                    at: [@pdf.bounds.left + 4, @pdf.cursor - 4],
                    width: @pdf.bounds.width - 8,
                    size: 10, style: :bold, color: DARK
      @pdf.move_down 22

      if section.lines.any?
        data = section.lines.map { |l| [l.label, amount_cell(l.amount_cents)] }
        col_w = @pdf.bounds.width
        @pdf.table(data, width: col_w,
          cell_style: { size: 9, padding: [3, 8], border_width: 0 },
          column_widths: [col_w * 0.72, col_w * 0.28]) do |t|
            t.columns(1).align = :right
            t.row_colors = %w[FFFFFF F8F8F8]
          end
      else
        @pdf.text "  #{I18n.t('accounting.cash_flow.no_activity')}",
                  size: 9, color: GRAY
        @pdf.move_down 4
      end

      total_color = section.total_cents >= 0 ? GREEN : RED
      data = [[I18n.t("accounting.cash_flow.net_#{section.name}"), amount_cell(section.total_cents)]]
      @pdf.table(data, width: @pdf.bounds.width,
        cell_style: { size: 10, padding: [5, 8], border_widths: [2, 0, 0, 0],
                      border_color: "374151", font_style: :bold, text_color: total_color },
        column_widths: [@pdf.bounds.width * 0.72, @pdf.bounds.width * 0.28]) do |t|
          t.columns(1).align = :right
        end
    end

    def render_net_summary
      rows = [
        [I18n.t("accounting.cash_flow.beginning_balance"), fmt(@cf.beginning_balance_cents)],
        [I18n.t("accounting.cash_flow.net_change"),        signed_fmt(@cf.net_change_cents)],
        [I18n.t("accounting.cash_flow.ending_balance"),    fmt(@cf.ending_balance_cents)]
      ]
      @pdf.table(rows, width: @pdf.bounds.width,
        cell_style: { size: 10, padding: [5, 8], border_widths: [1, 0, 0, 0],
                      border_color: AMBER, font_style: :bold },
        column_widths: [@pdf.bounds.width * 0.72, @pdf.bounds.width * 0.28]) do |t|
          t.columns(1).align = :right
          t.row(-1).border_widths = [2, 0, 0, 0]
          t.row(-1).border_color  = DARK
        end
    end

    def amount_cell(cents)
      cents >= 0 ? fmt(cents) : "(#{fmt(cents.abs)})"
    end

    def signed_fmt(cents)
      prefix = cents >= 0 ? "+" : "-"
      "#{prefix} #{fmt(cents.abs)}"
    end

    def fmt(cents)
      Money.new(cents.to_i.abs).format(symbol: "ج.م.")
    end
  end
end
