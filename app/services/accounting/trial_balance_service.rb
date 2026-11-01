# frozen_string_literal: true

module Accounting
  # Trial balance (ميزان المراجعة) read straight from the journal: per account,
  # the balance before the period, the period's debits and credits, and the
  # closing balance. Totals must agree — every entry is balanced on save, so a
  # gap means a line was written outside JournalEntry's validation.
  #
  # An account is its treasury when the line names one, else its account code.
  # Codes alone are not enough: before per-type code assignment was fixed, one
  # code was handed to several suppliers in turn, and a treasury's code has
  # since moved (a supplier's lines sit under 2013–2020 while it is now 2041).
  # Grouping by code would merge suppliers; grouping by treasury keeps each one.
  #
  # Treasury-backed accounts also carry their treasury's balance at the period
  # end, so a journal that disagrees with its sub-ledger shows up as a
  # difference rather than hiding behind a trial balance that still balances.
  #
  # No year-end close: a revenue or expense account's opening is everything
  # posted before the start date, so pick a range that starts on the first day
  # of the financial year to read it as a period P&L.
  class TrialBalanceService
    KEY_SQL = "COALESCE('t:' || journal_entry_lines.treasury_id::text, 'c:' || journal_entry_lines.account_code::text)"
    NET_SQL = "journal_entry_lines.debit_cents - journal_entry_lines.credit_cents"

    Account = Struct.new(:key, :code, :name, :account_type, :treasury, keyword_init: true) do
      def credit_normal? = %w[liability equity revenue].include?(account_type)
    end

    # Balances are signed debit-positive throughout; the view splits them into
    # debit and credit columns.
    Row = Struct.new(:account, :opening_cents, :debit_cents, :credit_cents, :treasury_cents, keyword_init: true) do
      def closing_cents = opening_cents + debit_cents - credit_cents

      # Journal minus treasury, in the account's own direction: positive means
      # the journal shows more than the treasury holds (or owes, for AP).
      def treasury_difference_cents
        return nil if treasury_cents.nil?

        journal = account.credit_normal? ? -closing_cents : closing_cents
        journal - treasury_cents
      end

      def difference? = treasury_difference_cents.to_i.nonzero?
    end

    # `rows` is what the table shows; `all_rows` is every account, so the
    # balanced check and the summary never judge a filtered subset.
    Result = Struct.new(:start_date, :end_date, :rows, :all_rows, keyword_init: true) do
      def summary = all_rows.equal?(rows) ? self : self.class.new(start_date: start_date, end_date: end_date, rows: all_rows, all_rows: all_rows)
      def groups = rows.group_by { |row| row.account.account_type }.sort_by { |type, _| JournalEntryLine::ACCOUNT_TYPES.index(type) || 99 }
      def opening_debit_cents = rows.sum { |row| [row.opening_cents, 0].max }
      def opening_credit_cents = rows.sum { |row| [-row.opening_cents, 0].max }
      def debit_cents = rows.sum(&:debit_cents)
      def credit_cents = rows.sum(&:credit_cents)
      def closing_debit_cents = rows.sum { |row| [row.closing_cents, 0].max }
      def closing_credit_cents = rows.sum { |row| [-row.closing_cents, 0].max }
      def balanced? = debit_cents == credit_cents && closing_debit_cents == closing_credit_cents
      def difference_count = rows.count(&:difference?)
    end

    # Every account the journal has ever touched, for the general ledger picker.
    def self.accounts
      # All history counts as movement, so an account that has netted to zero
      # is still listed.
      new(start_date: Date.new(1900, 1, 1), end_date: Date.new(9999, 12, 31)).call.rows.map(&:account)
        .sort_by { |account| [JournalEntryLine::ACCOUNT_TYPES.index(account.account_type) || 99, account.code.to_i] }
    end

    def self.account_for(key)
      return nil if key.blank?

      latest = latest_line_info([key])[key] or return nil
      build_account(key, latest, treasury_for(key))
    end

    def initialize(start_date:, end_date:, differences_only: false)
      @start_date = start_date
      @end_date = end_date
      @differences_only = differences_only
    end

    def call
      sums = journal_sums
      treasury_balances = treasury_balances_at_end
      # A treasury that moved without ever reaching the journal still belongs
      # in the list — that is the clearest difference of all.
      silent = treasury_balances.reject { |id, cents| cents.zero? || sums.key?("t:#{id}") }.keys
      keys = sums.keys + silent.map { |id| "t:#{id}" }

      latest = self.class.latest_line_info(sums.keys)
      treasuries = Treasury.where(id: keys.filter_map { |key| key.delete_prefix("t:") if key.start_with?("t:") }).index_by(&:id)

      rows = keys.filter_map do |key|
        treasury = treasuries[key.delete_prefix("t:")] if key.start_with?("t:")
        next if latest[key].nil? && treasury.nil?

        account = self.class.build_account(key, latest[key], treasury)
        opening, debit, credit = sums.fetch(key, [0, 0, 0])
        Row.new(account: account, opening_cents: opening, debit_cents: debit, credit_cents: credit,
                treasury_cents: treasury && treasury_balances.fetch(treasury.id, 0))
      end
      rows.reject! { |row| row.opening_cents.zero? && row.debit_cents.zero? && row.credit_cents.zero? && !row.difference? }
      rows.sort_by! { |row| [row.account.code.to_i, row.account.name.to_s] }
      shown = @differences_only ? rows.select(&:difference?) : rows

      Result.new(start_date: @start_date, end_date: @end_date, rows: shown, all_rows: rows)
    end

    # key => [opening, period debit, period credit] for every account with a
    # line on or before the end date.
    def journal_sums
      start = ActiveRecord::Base.connection.quote(@start_date)
      JournalEntryLine.joins(:journal_entry)
        .where(journal_entries: { date: ..@end_date })
        .group(Arel.sql(KEY_SQL))
        # Aliased: unnamed, every COALESCE comes back as a column called
        # "coalesce" and Rails casts the text key with the integer sums' type.
        .pluck(
          Arel.sql("#{KEY_SQL} AS account_key"),
          Arel.sql("COALESCE(SUM(#{NET_SQL}) FILTER (WHERE journal_entries.date < #{start}), 0) AS opening"),
          Arel.sql("COALESCE(SUM(journal_entry_lines.debit_cents) FILTER (WHERE journal_entries.date >= #{start}), 0) AS debit"),
          Arel.sql("COALESCE(SUM(journal_entry_lines.credit_cents) FILTER (WHERE journal_entries.date >= #{start}), 0) AS credit")
        )
        .to_h { |key, opening, debit, credit| [key, [opening.to_i, debit.to_i, credit.to_i]] }
    end

    # A treasury's balance on the end date, rebuilt from its own transactions
    # so a past period compares against the treasury as it stood then.
    def treasury_balances_at_end
      TreasuryTransaction.where(occurred_on: ..@end_date).group(:treasury_id).sum(:amount_cents)
    end

    # key => [code, name, type] from the account's most recent line, so a
    # renamed category reads under its current name.
    def self.latest_line_info(keys)
      return {} if keys.empty?

      quoted = keys.map { |key| ActiveRecord::Base.connection.quote(key) }.join(", ")
      JournalEntryLine.joins(:journal_entry)
        .where(Arel.sql("#{KEY_SQL} IN (#{quoted})"))
        .select(Arel.sql("DISTINCT ON (#{KEY_SQL}) #{KEY_SQL} AS account_key, journal_entry_lines.account_code, " \
                         "journal_entry_lines.account_name, journal_entry_lines.account_type"))
        .order(Arel.sql("#{KEY_SQL}, journal_entries.date DESC, journal_entry_lines.created_at DESC"))
        .to_a.to_h { |line| [line.account_key, [line.account_code, line.account_name, line.account_type]] }
    end

    def self.treasury_for(key)
      Treasury.find_by(id: key.delete_prefix("t:")) if key.start_with?("t:")
    end

    # A treasury's own account wins over what its old lines were posted as:
    # its code may have moved since.
    def self.build_account(key, latest, treasury)
      ref = treasury&.to_account
      code, name, type = latest
      Account.new(key: key, code: ref&.code || code, name: ref&.name || name,
                  account_type: ref&.account_type || type, treasury: treasury)
    end
  end
end
