# frozen_string_literal: true

module Accounting
  # One business day's drawers for a branch, shift by shift, with the day's totals
  # underneath — the end-of-day read a manager does over four shifts to see what
  # was taken, what was counted, and where it went.
  #
  # Every figure is derived from the same SessionSalesSummary the cashier's own
  # count screen uses, so the manager's view and the till's cannot disagree.
  class DrawerDayReport
    Row = Struct.new(:session, :summary, keyword_init: true) do
      def user = session.user
      def treasury = session.treasury
      def location = session.location
      def status = session.status
      def opened_at = session.created_at

      def opening_float_cents = summary.opening_float_cents
      def cash_cents = summary.cash_net_cents
      def instapay_cents = summary.instapay_cents
      def vodafone_cash_cents = summary.vodafone_cash_cents
      def total_sales_cents = summary.total_sales_cents
      def driver_payout_cents = summary.driver_payout_cents.to_i

      def expected_cents = session.expected_cash_cents.to_i
      def counted_cents = session.counted_cash_cents
      def variance_cents = session.variance_cents

      # Only a reconciled drawer has actually handed anything over.
      def deposited_cents
        return 0 unless session.deposit_treasury_id && counted_cents

        session.deposit_cents
      end

      def deposit_treasury = session.deposit_treasury
      def open? = session.status == "open"
    end

    Totals = Struct.new(
      :opening_float_cents, :cash_cents, :instapay_cents, :vodafone_cash_cents,
      :expected_cents, :counted_cents, :variance_cents, :deposited_cents,
      :driver_payout_cents, :shifts, :open_shifts,
      keyword_init: true
    ) do
      def total_sales_cents
        cash_cents + instapay_cents + vodafone_cash_cents
      end

      # What the day should have brought in once the drivers' delivery fees are
      # paid out of the drawers: expected cash (float aside) plus the wallets.
      def net_takings_cents
        total_sales_cents - driver_payout_cents
      end

      # The same, but with the cash as counted rather than as expected. A drawer
      # nobody has counted yet has no variance, so it adds its expected figure.
      def actual_takings_cents
        net_takings_cents + variance_cents
      end

      # A day is only closed when every drawer in it is.
      def fully_closed?
        shifts.positive? && open_shifts.zero?
      end
    end

    def self.call(date:, location: nil, treasury: nil)
      new(date: date, location: location, treasury: treasury).call
    end

    def initialize(date:, location: nil, treasury: nil)
      @date = date.to_date
      @location = location
      @treasury = treasury
    end

    def call
      rows = sessions.map { |session| Row.new(session: session, summary: SessionSalesSummary.for_session(session)) }
      [rows, totals_for(rows)]
    end

    private

    def sessions
      scope = CashDrawerSession.where(session_date: @date)
                               .includes(:user, :treasury, :location, :deposit_treasury)
                               .order(:created_at)
      scope = scope.where(location_id: @location.id) if @location
      scope = scope.where(treasury_id: @treasury.id) if @treasury
      scope
    end

    def totals_for(rows)
      Totals.new(
        opening_float_cents: rows.sum(&:opening_float_cents),
        cash_cents: rows.sum(&:cash_cents),
        instapay_cents: rows.sum(&:instapay_cents),
        vodafone_cash_cents: rows.sum(&:vodafone_cash_cents),
        expected_cents: rows.sum(&:expected_cents),
        # A drawer nobody has counted yet contributes nothing rather than a zero
        # that would read as "counted, and empty".
        counted_cents: rows.sum { |r| r.counted_cents.to_i },
        variance_cents: rows.sum { |r| r.variance_cents.to_i },
        deposited_cents: rows.sum(&:deposited_cents),
        driver_payout_cents: rows.sum(&:driver_payout_cents),
        shifts: rows.size,
        open_shifts: rows.count(&:open?)
      )
    end
  end
end
