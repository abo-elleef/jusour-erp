# frozen_string_literal: true

module Accounting
  # General ledger (دفتر الأستاذ) for one account: the balance before the
  # period, then every journal line in it with a running balance. The account is
  # the same key the trial balance uses — its treasury, else its code — so a
  # trial balance row opens onto exactly the lines that made its number.
  #
  # Balances are debit-positive, like the trial balance.
  class GeneralLedgerService
    attr_reader :account

    def initialize(account:, start_date:, end_date:)
      @account = account
      @start_date = start_date
      @end_date = end_date
    end

    def opening_cents
      @opening_cents ||= scope.where(journal_entries: { date: ...@start_date })
        .sum(Arel.sql(TrialBalanceService::NET_SQL)).to_i
    end

    def debit_cents = totals.first
    def credit_cents = totals.last
    def closing_cents = opening_cents + debit_cents - credit_cents
    def line_count = period_scope.count

    # The period's lines oldest first, each carrying `balance_cents` — the
    # running balance after it, opening included. Computed by a window over the
    # whole period, so a page of it still shows the true running balance.
    def lines
      period_scope
        .select(
          "journal_entry_lines.*",
          "journal_entries.date AS entry_date",
          "journal_entries.entry_number",
          "journal_entries.description AS entry_description",
          "#{opening_cents} + SUM(#{TrialBalanceService::NET_SQL}) OVER (ORDER BY #{ORDER_SQL}) AS balance_cents"
        )
        .order(Arel.sql(ORDER_SQL))
    end

    ORDER_SQL = "journal_entries.date, journal_entries.entry_number, journal_entry_lines.created_at, journal_entry_lines.id"

    private

    def totals
      @totals ||= period_scope.pick(
        Arel.sql("COALESCE(SUM(journal_entry_lines.debit_cents), 0) AS debit"),
        Arel.sql("COALESCE(SUM(journal_entry_lines.credit_cents), 0) AS credit")
      ).map(&:to_i)
    end

    def period_scope
      scope.where(journal_entries: { date: @start_date..@end_date })
    end

    def scope
      JournalEntryLine.joins(:journal_entry).where("#{TrialBalanceService::KEY_SQL} = ?", @account.key)
    end
  end
end
