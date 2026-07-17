# frozen_string_literal: true

require "prawn/table"

module Accounting
  class FinancialStatementPdfService
    AMBER = "D97706"
    GRAY  = "6B7280"
    DARK  = "111827"
    GREEN = "065F46"
    RED   = "991B1B"
    LIGHT = "F9FAFB"

    def initialize(type, coa, start_date, end_date, company)
      @type  = type
      @coa   = coa
      @start = start_date
      @end   = end_date
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

        case @type
        when :profit_loss   then render_profit_loss
        when :balance_sheet then render_balance_sheet
        end

        render_footer
      end.render
    end

    private

    def render_header
      @pdf.text @company.name, size: 18, style: :bold, color: DARK
      @pdf.text statement_title, size: 13, color: GRAY
      @pdf.text date_subtitle, size: 10, color: GRAY
      @pdf.move_down 4
      @pdf.stroke_color AMBER
      @pdf.stroke_horizontal_rule
    end

    def render_footer
      @pdf.number_pages(
        "<page> / <total>",
        at: [@pdf.bounds.left, 0],
        align: :right,
        size: 8,
        color: GRAY
      )
    end

    def render_profit_loss
      # Revenue section
      section_heading I18n.t("accounting.financial_statements.revenue")
      account_rows(@coa.revenue_lines)
      total_row I18n.t("accounting.financial_statements.total_revenue"), @coa.total_revenue_cents

      @pdf.move_down 14

      # Expenses section
      section_heading I18n.t("accounting.financial_statements.expenses")
      account_rows(@coa.expense_lines)
      total_row I18n.t("accounting.financial_statements.total_expenses"), @coa.total_expenses_cents

      @pdf.move_down 20

      # Net Income
      net = @coa.net_income_cents
      color = net >= 0 ? GREEN : RED
      data = [[
        I18n.t("accounting.financial_statements.net_income"),
        fmt(net.abs) + (net < 0 ? " (#{I18n.t('accounting.financial_statements.loss')})" : "")
      ]]
      @pdf.table(data, width: @pdf.bounds.width,
        cell_style: { size: 11, padding: [6, 8], border_widths: [2, 0, 0, 0],
                      border_color: AMBER, font_style: :bold, text_color: color })
    end

    def render_balance_sheet
      col_w = @pdf.bounds.width

      # Assets
      section_heading I18n.t("accounting.financial_statements.current_assets")
      account_rows(@coa.current_asset_lines)
      subtotal_row I18n.t("accounting.financial_statements.total_current_assets"), @coa.total_current_assets_cents

      if @coa.non_current_asset_lines.any?
        @pdf.move_down 10
        section_heading I18n.t("accounting.financial_statements.non_current_assets")
        account_rows(@coa.non_current_asset_lines)
        subtotal_row I18n.t("accounting.financial_statements.total_non_current_assets"), @coa.total_non_current_assets_cents
      end

      total_row I18n.t("accounting.financial_statements.total_assets"), @coa.total_assets_cents
      @pdf.move_down 16

      # Liabilities
      section_heading I18n.t("accounting.financial_statements.liabilities")
      account_rows(@coa.liability_lines)
      total_row I18n.t("accounting.financial_statements.total_liabilities"), @coa.total_liabilities_cents
      @pdf.move_down 16

      # Equity
      section_heading I18n.t("accounting.financial_statements.equity")
      account_rows(@coa.equity_lines)
      total_row I18n.t("accounting.financial_statements.total_equity"), @coa.total_equity_cents

      @pdf.move_down 20
      data = [[
        I18n.t("accounting.financial_statements.liabilities_plus_equity"),
        fmt(@coa.total_liabilities_cents + @coa.total_equity_cents)
      ]]
      @pdf.table(data, width: col_w,
        cell_style: { size: 11, padding: [6, 8], border_widths: [2, 0, 0, 0],
                      border_color: AMBER, font_style: :bold })
    end

    def section_heading(title)
      @pdf.fill_color LIGHT
      @pdf.fill_rectangle [@pdf.bounds.left, @pdf.cursor], @pdf.bounds.width, 18
      @pdf.fill_color DARK
      @pdf.text_box title, at: [@pdf.bounds.left + 4, @pdf.cursor - 4],
                    width: @pdf.bounds.width - 8, size: 10, style: :bold, color: DARK
      @pdf.move_down 20
    end

    def account_rows(lines)
      return if lines.empty?

      data = lines.map { |l| [account_label(l), fmt(l.balance_cents)] }
      @pdf.table(data, width: @pdf.bounds.width,
        cell_style: { size: 9, padding: [3, 8], border_width: 0, border_color: "EEEEEE" },
        column_widths: [@pdf.bounds.width * 0.72, @pdf.bounds.width * 0.28]) do |t|
          t.columns(1).align = :right
          t.row_colors = %w[FFFFFF F8F8F8]
        end
    end

    def subtotal_row(label, cents)
      data = [[label, fmt(cents)]]
      @pdf.table(data, width: @pdf.bounds.width,
        cell_style: { size: 9, padding: [4, 8], border_widths: [0, 0, 1, 0],
                      border_color: "DDDDDD", font_style: :bold, text_color: GRAY },
        column_widths: [@pdf.bounds.width * 0.72, @pdf.bounds.width * 0.28]) do |t|
          t.columns(1).align = :right
        end
    end

    def total_row(label, cents)
      data = [[label, fmt(cents)]]
      @pdf.table(data, width: @pdf.bounds.width,
        cell_style: { size: 10, padding: [5, 8], border_widths: [2, 0, 0, 0],
                      border_color: "374151", font_style: :bold },
        column_widths: [@pdf.bounds.width * 0.72, @pdf.bounds.width * 0.28]) do |t|
          t.columns(1).align = :right
        end
    end

    def account_label(line)
      "  #{line.code}  #{line.name}"
    end

    def fmt(cents)
      Money.new(cents.to_i.abs).format(symbol: "ج.م.")
    end

    def statement_title
      case @type
      when :profit_loss   then I18n.t("accounting.financial_statements.profit_loss_title")
      when :balance_sheet then I18n.t("accounting.financial_statements.balance_sheet_title")
      end
    end

    def date_subtitle
      case @type
      when :profit_loss
        "#{I18n.l(@start, format: :long)} – #{I18n.l(@end, format: :long)}"
      when :balance_sheet
        "#{I18n.t('accounting.financial_statements.as_of')} #{I18n.l(@end, format: :long)}"
      end
    end
  end
end
