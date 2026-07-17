# frozen_string_literal: true

module Admin
  module Accounting
    class FinancialStatementsController < BaseController
      def profit_loss
        @start_date = params[:start_date]&.to_date || Date.current.beginning_of_year
        @end_date   = params[:end_date]&.to_date   || Date.current
        @coa = ::Accounting::ChartOfAccountsService.new(start_date: @start_date, end_date: @end_date)

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
    end
  end
end
