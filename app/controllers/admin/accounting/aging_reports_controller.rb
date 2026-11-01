# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # AR and AP aging (أعمار الديون) — one company-wide report per side, built
    # by ::Accounting::AgingReportService. Always as of today: an invoice's
    # balance is stored, not dated, so a past "as of" would need every payment
    # and credit replayed.
    #
    # No pagination on purpose: the totals row and the column sort must cover
    # every party, and the list is bounded by parties that actually owe or are
    # owed money.
    class AgingReportsController < BaseController
      helper_method :print_mode?

      def receivable
        raise Pundit::NotAuthorizedError unless Current.company&.feature_enabled?(:ar_credit_sales)

        render_report(:receivable)
      end

      def payable
        render_report(:payable)
      end

      private

      def render_report(side)
        @side = side
        @overdue_only = params[:overdue_only] == "1"
        @result = ::Accounting::AgingReportService.new(side, overdue_only: @overdue_only).call

        respond_to do |format|
          format.html { render :report }
          format.csv do
            send_data "﻿#{report_csv}", filename: "#{side}-aging-#{@result.as_of}.csv",
                                            type: "text/csv; charset=utf-8"
          end
        end
      end

      def print_mode?
        params[:print].present?
      end

      def report_csv
        bucket_headers = ::Accounting::AgingBuckets::ALL.map { |bucket| t("accounting.aging.buckets.#{bucket}") }
        CSV.generate do |csv|
          csv << [t("accounting.aging.#{@side}.title"), @result.as_of.to_s,
                  (t("accounting.aging.overdue_only") if @overdue_only)].compact
          csv << [t("accounting.aging.#{@side}.party"), t("accounting.aging.table.invoices"), *bucket_headers,
                  t("accounting.aging.table.total"), t("accounting.aging.table.oldest_days"),
                  t("accounting.aging.table.ledger"), t("accounting.aging.table.unallocated")]
          @result.rows.each do |row|
            csv << [::Accounting::AgingReportService.party_name(row.party), row.invoice_count,
                    *::Accounting::AgingBuckets::ALL.map { |bucket| csv_amount(row.buckets[bucket]) },
                    csv_amount(row.invoiced_cents), row.oldest_days,
                    csv_amount(row.ledger_cents), csv_amount(row.unallocated_cents)]
          end
          csv << [t("accounting.aging.table.grand_total"), @result.invoice_count,
                  *::Accounting::AgingBuckets::ALL.map { |bucket| csv_amount(@result.bucket_cents(bucket)) },
                  csv_amount(@result.invoiced_cents), nil,
                  csv_amount(@result.ledger_cents), csv_amount(@result.unallocated_cents)]
        end
      end

      # Plain decimals, not formatted money: the file is opened in a spreadsheet
      # to be added up.
      def csv_amount(cents)
        format("%.2f", cents.to_d / 100)
      end
    end
  end
end
