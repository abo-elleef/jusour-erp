# frozen_string_literal: true

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

        if operating_kinds.include?(@kind) || investing_kinds.include?(@kind)
          @transactions = ::TreasuryTransaction
            .joins(:treasury)
            .where(treasuries: { company_id: ::Current.company.id })
            .where.not(treasuries: { treasury_type: "supplier_ap" })
            .where(occurred_on: @start_date..@end_date, kind: @kind)
            .includes(:treasury)
            .order(occurred_on: :desc)
          render :cash_flow_lines_treasury
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
          render :cash_flow_lines_je
        else
          redirect_to cash_flow_admin_accounting_financial_statements_path(
            start_date: @start_date, end_date: @end_date
          )
        end
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
    end
  end
end
