# frozen_string_literal: true

module Accounting
  # Cash movement summary for a period: per money treasury (cash drawers, safes,
  # banks, wallets — not the supplier/customer ledgers), the balance before the
  # period, money in, money out, net transfers between treasuries, and the
  # closing balance. Balances are rebuilt from the treasury's own transactions,
  # as the trial balance does, so a past period reads as it stood then.
  #
  # Transfers are kept apart from in/out: moving 10,000 from a drawer to the
  # safe is not income or spending, and counting it twice would swell both.
  class TreasuryMovementService
    TRANSFER = "transfer"

    Row = Struct.new(:treasury, :opening_cents, :in_cents, :out_cents, :transfer_cents, keyword_init: true) do
      def closing_cents = opening_cents + in_cents - out_cents + transfer_cents
    end

    # Money in and out by kind of movement, every treasury together.
    Kind = Struct.new(:kind, :in_cents, :out_cents, :count, keyword_init: true)

    Result = Struct.new(:rows, :kinds, keyword_init: true) do
      def groups = rows.group_by { |row| row.treasury.treasury_type }
      %i[opening_cents in_cents out_cents transfer_cents closing_cents].each do |attr|
        define_method(attr) { rows.sum(&attr) }
      end
    end

    def initialize(start_date:, end_date:, user:)
      @start_date = start_date
      @end_date = end_date
      @user = user
    end

    def call
      treasuries = Treasury.payable.visible_to(@user).ordered.to_a
      sums = period_sums(treasuries.map(&:id))

      rows = treasuries.filter_map do |treasury|
        opening, inflow, outflow, transfer = sums.fetch(treasury.id, [0, 0, 0, 0])
        next if [opening, inflow, outflow, transfer].all?(&:zero?)

        Row.new(treasury: treasury, opening_cents: opening, in_cents: inflow, out_cents: outflow, transfer_cents: transfer)
      end

      Result.new(rows: rows, kinds: kinds(treasuries.map(&:id)))
    end

    private

    def transactions(ids) = TreasuryTransaction.where(treasury_id: ids)

    # treasury_id => [opening, in, out, net transfers]
    def period_sums(ids)
      start = ActiveRecord::Base.connection.quote(@start_date)
      in_period = "occurred_on >= #{start}"
      transactions(ids).where(occurred_on: ..@end_date).group(:treasury_id)
        .pluck(
          :treasury_id,
          Arel.sql("COALESCE(SUM(amount_cents) FILTER (WHERE occurred_on < #{start}), 0) AS opening"),
          Arel.sql("COALESCE(SUM(amount_cents) FILTER (WHERE #{in_period} AND kind <> '#{TRANSFER}' AND amount_cents > 0), 0) AS money_in"),
          Arel.sql("COALESCE(-SUM(amount_cents) FILTER (WHERE #{in_period} AND kind <> '#{TRANSFER}' AND amount_cents < 0), 0) AS money_out"),
          Arel.sql("COALESCE(SUM(amount_cents) FILTER (WHERE #{in_period} AND kind = '#{TRANSFER}'), 0) AS transfers")
        )
        .to_h { |id, *values| [id, values.map(&:to_i)] }
    end

    def kinds(ids)
      transactions(ids).where(occurred_on: @start_date..@end_date).where.not(kind: TRANSFER)
        .group(:kind)
        .pluck(:kind,
               Arel.sql("COALESCE(SUM(amount_cents) FILTER (WHERE amount_cents > 0), 0) AS money_in"),
               Arel.sql("COALESCE(-SUM(amount_cents) FILTER (WHERE amount_cents < 0), 0) AS money_out"),
               Arel.sql("COUNT(*) AS movements"))
        .map { |kind, inflow, outflow, count| Kind.new(kind: kind, in_cents: inflow.to_i, out_cents: outflow.to_i, count: count) }
        .sort_by { |kind| -(kind.in_cents + kind.out_cents) }
    end
  end
end
