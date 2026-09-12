# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class FinancialStatementsController < BaseController
      def profit_loss
        parse_date_range(default_start: Date.current.beginning_of_year)
        @coa = ::Accounting::ChartOfAccountsService.new(start_date: @start_date, end_date: @end_date)

        @opening_snapshot = InventorySnapshot.where(company: Current.company)
          .on_or_before(@start_date).first
        @closing_snapshot = InventorySnapshot.where(company: Current.company)
          .on_or_before(@end_date).first

        # Opening and closing may be the same snapshot if the same date was chosen;
        # closing should be <= end_date and opening <= start_date and != closing.
        if @opening_snapshot && @closing_snapshot && @opening_snapshot.id == @closing_snapshot.id
          @opening_snapshot = nil
        end

        @opening_cents = @opening_snapshot&.value_cents.to_i
        @closing_cents = @closing_snapshot&.value_cents.to_i

        respond_to do |format|
          format.html
          format.pdf do
            pdf = ::Accounting::FinancialStatementPdfService.new(
              :profit_loss, @coa, @start_date, @end_date, Current.company
            ).render
            send_data pdf,
                      filename: "profit_loss_#{@start_date}_#{@end_date}.pdf",
                      type: "application/pdf",
                      disposition: "inline"
          end
        end
      end

      def balance_sheet_lines
        @as_of        = params[:as_of]&.to_date || Date.current
        @account_code = params[:account_code].to_i
        @account_name = params[:account_name].to_s

        @je_lines = ::JournalEntryLine
          .joins(:journal_entry)
          .where(journal_entries: { company_id: ::Current.company.id })
          .where(account_code: @account_code)
          .where("journal_entries.date <= ?", @as_of)
          .includes(:journal_entry)
          .order("journal_entries.date DESC")

        @balance_cents = @je_lines.sum("credit_cents - debit_cents")
      end

      def balance_sheet
        @as_of = params[:as_of]&.to_date || Date.current
        @coa = ::Accounting::ChartOfAccountsService.new(
          start_date: @as_of.beginning_of_year,
          end_date: @as_of
        )

        respond_to do |format|
          format.html
          format.pdf do
            pdf = ::Accounting::FinancialStatementPdfService.new(
              :balance_sheet, @coa, nil, @as_of, Current.company
            ).render
            send_data pdf,
                      filename: "balance_sheet_#{@as_of}.pdf",
                      type: "application/pdf",
                      disposition: "inline"
          end
        end
      end

      def update_inventory_snapshot
        date_str  = params[:snapshot_date].presence
        value_str = params[:value_cents_input].presence
        return head :bad_request unless date_str && value_str

        date       = Date.parse(date_str) rescue nil
        return head :bad_request unless date

        value_cents = (value_str.to_d * 100).round
        snapshot = InventorySnapshot.find_or_build_for(date, company: Current.company)
        snapshot.value_cents = value_cents
        snapshot.save!

        redirect_to profit_loss_admin_accounting_financial_statements_path(
          start_date: params[:start_date], end_date: params[:end_date]
        ), notice: t("accounting.financial_statements.snapshot_saved")
      end

      def cash_flow_lines
        parse_date_range(default_start: Date.current.beginning_of_year)
        @kind       = params[:kind].to_s
        @cf         = ::Accounting::CashFlowService.new(start_date: @start_date, end_date: @end_date)

        operating_kinds  = ::Accounting::CashFlowService::OPERATING_KINDS
        investing_kinds  = ::Accounting::CashFlowService::INVESTING_KINDS
        financing_kinds  = %w[loan_proceeds loan_repayment capital_contribution partner_drawings]

        if operating_kinds.include?(@kind) || investing_kinds.include?(@kind) ||
           @kind == ::Accounting::CashFlowService::JOURNAL_ENTRY_KIND
          @transactions = ::TreasuryTransaction
            .joins(:treasury)
            .where(treasuries: { company_id: ::Current.company.id })
            .where.not(treasuries: { treasury_type: "supplier_ap" })
            .where(occurred_on: @start_date..@end_date, kind: @kind)
            .includes(:treasury)
            .order(occurred_on: :desc)
          # The statement excludes financing entries from this line, so the
          # drill-down has to exclude them too or the rows will not add up to it.
          if @kind == ::Accounting::CashFlowService::JOURNAL_ENTRY_KIND
            @transactions = @transactions.where(id: @cf.journal_entry_transactions.select(:id))
          end
          respond_to do |format|
            format.html { render :cash_flow_lines_treasury }
            format.csv  { send_cash_flow_lines_csv(treasury_lines_csv) }
          end
        elsif financing_kinds.include?(@kind)
          # Financing reads cash movement, not journal lines, so the drill-down
          # has to read the same transactions or the rows will not add up to the
          # line they came from.
          inflow = %w[loan_proceeds capital_contribution].include?(@kind)
          @transactions = @cf.financing_transactions_for(params[:account_code])
            .where(inflow ? "treasury_transactions.amount_cents > 0" : "treasury_transactions.amount_cents < 0")
            .includes(:treasury)
            .order(occurred_on: :desc)
          respond_to do |format|
            format.html { render :cash_flow_lines_treasury }
            format.csv  { send_cash_flow_lines_csv(treasury_lines_csv) }
          end
        else
          redirect_to cash_flow_admin_accounting_financial_statements_path(
            start_date: @start_date, end_date: @end_date
          )
        end
      end

      # Why the P&L's profit and the cash flow's net change differ. Same date
      # range, same two numbers those pages show, with the gap itemised.
      def profit_vs_cash
        parse_date_range(default_start: Date.current.beginning_of_year)
        @bridge = ::Accounting::ProfitVsCashService.new(start_date: @start_date, end_date: @end_date)
      end

      def cash_flow
        parse_date_range(default_start: Date.current.beginning_of_year)
        @cf = ::Accounting::CashFlowService.new(start_date: @start_date, end_date: @end_date)

        respond_to do |format|
          format.html
          format.pdf do
            pdf = ::Accounting::CashFlowPdfService.new(
              @cf, @start_date, @end_date, Current.company
            ).render
            send_data pdf,
                      filename: "cash_flow_#{@start_date}_#{@end_date}.pdf",
                      type: "application/pdf",
                      disposition: "inline"
          end
        end
      end

      private

      # UTF-8 BOM so Excel renders the Arabic columns instead of mojibake — the
      # same trick the other exports use.
      def send_cash_flow_lines_csv(body)
        send_data "\ufeff#{body}",
          filename: "cash-flow-#{@kind}-#{@start_date}-#{@end_date}.csv",
          type: "text/csv; charset=utf-8"
      end

      # Amounts go out as plain decimals, not formatted money: a spreadsheet has
      # to be able to sum the column, and thousands separators break that.
      def csv_amount(cents)
        format("%.2f", cents.to_d / 100)
      end

      def treasury_lines_csv
        CSV.generate do |csv|
          csv << [t("shared.date"), t("accounting.cash_flow.treasury"),
                  t("shared.notes"), t("shared.amount")]
          @transactions.each do |tx|
            csv << [tx.occurred_on, tx.treasury.name, tx.description, csv_amount(tx.amount_cents)]
          end
          csv << []
          csv << [t("shared.total"), nil, nil, csv_amount(@transactions.sum(:amount_cents))]
        end
      end
    end
  end
end
