# frozen_string_literal: true

module Accounting
  # One employee's account as a statement: the entries in a date range, each
  # with the running balance after it, plus the balance carried in from before
  # the range. Positive is owed to them, negative is owed by them — the same
  # sign as User#staff_balance_cents.
  #
  # The running balance is taken over the whole account, not just the range,
  # so a row reads the same whichever page or range it is seen on.
  class StaffStatementService
    attr_reader :from, :to

    def initialize(user, from: nil, to: nil)
      @user = user
      @from = from
      @to = to
    end

    # Oldest first, as a statement reads, each line carrying
    # `running_balance_cents`.
    def lines
      scope = JournalEntryLine.from(running_lines, :journal_entry_lines)
                              .joins(:journal_entry)
                              .includes(journal_entry: :source_record)
      scope = scope.where(journal_entries: { date: @from.. }) if @from
      scope = scope.where(journal_entries: { date: ..@to }) if @to
      scope.order(Arel.sql("journal_entries.date, journal_entries.entry_number, journal_entry_lines.id"))
    end

    # Balance before the range starts; nil when the range is open-ended.
    def opening_balance_cents
      return nil unless @from

      sum_signed(account_lines.where(journal_entries: { date: ...@from }))
    end

    def closing_balance_cents
      scope = account_lines
      scope = scope.where(journal_entries: { date: ..@to }) if @to
      sum_signed(scope)
    end

    def range_debit_cents  = range_lines.sum(:debit_cents)
    def range_credit_cents = range_lines.sum(:credit_cents)

    private

    def account_lines
      JournalEntryLine.joins(:journal_entry)
                      .where(journal_entries: { company_id: @user.company_id }, account_code: @user.account_code)
    end

    def range_lines
      scope = account_lines
      scope = scope.where(journal_entries: { date: @from.. }) if @from
      scope = scope.where(journal_entries: { date: ..@to }) if @to
      scope
    end

    def running_lines
      account_lines.select(
        "journal_entry_lines.*",
        "SUM(journal_entry_lines.credit_cents - journal_entry_lines.debit_cents) OVER (" \
        "ORDER BY journal_entries.date, journal_entries.entry_number, journal_entry_lines.id" \
        ") AS running_balance_cents"
      )
    end

    def sum_signed(scope) = scope.sum(:credit_cents) - scope.sum(:debit_cents)
  end
end
