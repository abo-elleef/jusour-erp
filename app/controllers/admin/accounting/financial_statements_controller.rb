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
          @je_lines = ::JournalEntryLine
            .joins(:journal_entry)
            .where(journal_entries: { company_id: ::Current.company.id, date: @start_date..@end_date })
            .then do |scope|
              case @kind
              when "loan_proceeds"
                loan_codes = ::Loan.where(company_id: ::Current.company.id).pluck(:account_code)
                scope.where(account_code: loan_codes).where("credit_cents > 0")
              when "loan_repayment"
                loan_codes = ::Loan.where(company_id: ::Current.company.id).pluck(:account_code)
                scope.where(account_code: loan_codes).where("debit_cents > 0")
              when "capital_contribution"
                partner_codes = ::Partner.where(company_id: ::Current.company.id).pluck(:account_code)
                scope.where(account_code: partner_codes).where("credit_cents > 0")
              when "partner_drawings"
                partner_codes = ::Partner.where(company_id: ::Current.company.id).pluck(:account_code)
                scope.where(account_code: partner_codes).where("debit_cents > 0")
              end
            end
            .includes(:journal_entry)
            .order("journal_entries.date DESC")
          respond_to do |format|
            format.html { render :cash_flow_lines_je }
            format.csv  { send_cash_flow_lines_csv(je_lines_csv) }
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

      def je_lines_csv
        credit_kinds = %w[loan_proceeds capital_contribution]
        CSV.generate do |csv|
          csv << [t("shared.date"), t("accounting.cash_flow.journal_entry"),
                  t("accounting.journal_entries.col.code"),
                  t("shared.notes"), t("shared.amount")]
          total = 0
          @je_lines.each do |jel|
            # Signed like the treasury export and like the statement's own total:
            # money in is positive, a repayment or drawing is negative. (The HTML
            # table prints the row unsigned and only the footer carries the sign.)
            amount = @kind.in?(credit_kinds) ? jel.credit_cents : -jel.debit_cents
            total += amount
            csv << [
              jel.journal_entry.date,
              jel.journal_entry.entry_number,
              jel.account_code,
              jel.notes.presence || jel.journal_entry.description,
              csv_amount(amount)
            ]
          end
          csv << []
          csv << [t("shared.total"), nil, nil, nil, csv_amount(total)]
        end
      end
    end
  end
end
