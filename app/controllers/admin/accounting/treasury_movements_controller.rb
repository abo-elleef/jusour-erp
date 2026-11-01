# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # Cash movement summary across money treasuries
    # (::Accounting::TreasuryMovementService). Same permission as the treasury
    # pages it summarises. Not paginated: the totals must cover every treasury,
    # and the list is bounded by the company's treasuries.
    class TreasuryMovementsController < BaseController
      helper_method :print_mode?

      def index
        parse_date_range(default_start: Date.current.beginning_of_month)
        @result = ::Accounting::TreasuryMovementService.new(start_date: @start_date, end_date: @end_date, user: current_user).call

        respond_to do |format|
          format.html
          format.csv do
            send_data "﻿#{movements_csv}", filename: "treasury-movements-#{@start_date}-#{@end_date}.csv",
                                               type: "text/csv; charset=utf-8"
          end
        end
      end

      private

      def print_mode?
        params[:print].present?
      end

      def movements_csv
        CSV.generate do |csv|
          csv << [t("accounting.treasury_movements.title"), @start_date.to_s, @end_date.to_s]
          csv << [t("accounting.treasury_movements.table.treasury"), t("accounting.treasury_movements.table.type"),
                  *%w[opening in out transfers closing].map { |key| t("accounting.treasury_movements.table.#{key}") }]
          @result.rows.each do |row|
            csv << [row.treasury.name, helpers.accounting_treasury_type(row.treasury.treasury_type),
                    *amounts(row)]
          end
          csv << [t("accounting.treasury_movements.table.total"), nil, *amounts(@result)]
        end
      end

      def amounts(source)
        %i[opening_cents in_cents out_cents transfer_cents closing_cents].map { |attr| format("%.2f", source.public_send(attr).to_d / 100) }
      end
    end
  end
end
