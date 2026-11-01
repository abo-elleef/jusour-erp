# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # Trial balance and general ledger by account, both read from the journal
    # (::Accounting::TrialBalanceService / GeneralLedgerService). The trial
    # balance is not paginated — its totals must cover every account and the
    # list is bounded by the chart of accounts. The ledger pages its lines; CSV
    # and print take every line.
    class LedgerReportsController < BaseController
      LEDGER_PAGE_SIZE = 100

      helper_method :print_mode?

      def trial_balance
        parse_date_range(default_start: Date.current.beginning_of_year)
        @differences_only = params[:differences_only] == "1"
        @result = ::Accounting::TrialBalanceService.new(
          start_date: @start_date, end_date: @end_date, differences_only: @differences_only
        ).call

        respond_to do |format|
          format.html
          format.csv { send_report_csv(trial_balance_csv, "trial-balance") }
        end
      end

      def general_ledger
        parse_date_range(default_start: Date.current.beginning_of_year)
        @accounts = ::Accounting::TrialBalanceService.accounts
        @account = ::Accounting::TrialBalanceService.account_for(params[:account])
        return render(:general_ledger) unless @account

        @ledger = ::Accounting::GeneralLedgerService.new(account: @account, start_date: @start_date, end_date: @end_date)
        if print_mode? || request.format.csv?
          @lines = @ledger.lines.to_a
        else
          @pagy, @lines = pagy(:offset, @ledger.lines, limit: LEDGER_PAGE_SIZE, count: @ledger.line_count)
        end

        respond_to do |format|
          format.html
          format.csv { send_report_csv(general_ledger_csv, "general-ledger-#{@account.code}") }
        end
      end

      private

      def print_mode?
        params[:print].present?
      end

      def send_report_csv(body, name)
        send_data "﻿#{body}", filename: "#{name}-#{@start_date}-#{@end_date}.csv",
                                  type: "text/csv; charset=utf-8"
      end

      def trial_balance_csv
        CSV.generate do |csv|
          csv << [t("accounting.ledger.trial_balance.title"), @start_date.to_s, @end_date.to_s,
                  (t("accounting.ledger.trial_balance.differences_only") if @differences_only)].compact
          csv << [t("accounting.ledger.table.code"), t("accounting.ledger.table.account"), t("accounting.ledger.table.type"),
                  "#{t('accounting.ledger.table.opening')} #{t('accounting.ledger.debit')}",
                  "#{t('accounting.ledger.table.opening')} #{t('accounting.ledger.credit')}",
                  "#{t('accounting.ledger.table.period')} #{t('accounting.ledger.debit')}",
                  "#{t('accounting.ledger.table.period')} #{t('accounting.ledger.credit')}",
                  "#{t('accounting.ledger.table.closing')} #{t('accounting.ledger.debit')}",
                  "#{t('accounting.ledger.table.closing')} #{t('accounting.ledger.credit')}",
                  t("accounting.ledger.table.treasury_difference")]
          @result.rows.each do |row|
            csv << [row.account.code, row.account.name, t("accounting.journal_entries.account_types.#{row.account.account_type}"),
                    *split_csv(row.opening_cents), csv_amount(row.debit_cents), csv_amount(row.credit_cents),
                    *split_csv(row.closing_cents),
                    row.treasury_difference_cents && csv_amount(row.treasury_difference_cents)]
          end
          csv << [t("accounting.ledger.table.total"), nil, nil,
                  csv_amount(@result.opening_debit_cents), csv_amount(@result.opening_credit_cents),
                  csv_amount(@result.debit_cents), csv_amount(@result.credit_cents),
                  csv_amount(@result.closing_debit_cents), csv_amount(@result.closing_credit_cents)]
        end
      end

      def general_ledger_csv
        CSV.generate do |csv|
          csv << [t("accounting.ledger.general_ledger.title"), @account.code, @account.name, @start_date.to_s, @end_date.to_s]
          csv << [t("accounting.ledger.table.date"), t("accounting.ledger.table.entry"), t("accounting.ledger.table.description"),
                  t("accounting.ledger.debit"), t("accounting.ledger.credit"), t("accounting.ledger.table.balance")]
          csv << [nil, nil, t("accounting.ledger.general_ledger.opening_balance"), nil, nil, csv_amount(@ledger.opening_cents)]
          @lines.each do |line|
            csv << [line.entry_date.to_s, line.entry_number, [line.entry_description, line.notes.presence].compact.join(" — "),
                    csv_amount(line.debit_cents), csv_amount(line.credit_cents), csv_amount(line.balance_cents)]
          end
          csv << [nil, nil, t("accounting.ledger.general_ledger.closing_balance"),
                  csv_amount(@ledger.debit_cents), csv_amount(@ledger.credit_cents), csv_amount(@ledger.closing_cents)]
        end
      end

      # A signed debit-positive balance as [debit, credit] cells.
      def split_csv(cents)
        [csv_amount([cents, 0].max), csv_amount([-cents, 0].max)]
      end

      # Plain decimals, not formatted money: the file is opened in a spreadsheet
      # to be added up. Balances in the ledger CSV stay signed, debit positive.
      def csv_amount(cents)
        format("%.2f", cents.to_d / 100)
      end
    end
  end
end
