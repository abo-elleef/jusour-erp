# frozen_string_literal: true

module Accounting
  # Manager end-of-day check: sum cashiers' InstaPay / Vodafone sales vs statement totals.
  class DigitalWalletDayCloseReport
    Row = Struct.new(:session, :user, :instapay_cents, :vodafone_cash_cents, :status, keyword_init: true) do
      def total_digital_cents
        instapay_cents + vodafone_cash_cents
      end
    end

    Summary = Struct.new(
      :date,
      :rows,
      :expected_instapay_cents,
      :expected_vodafone_cash_cents,
      :statement_instapay_cents,
      :statement_vodafone_cash_cents,
      :day_close,
      keyword_init: true
    ) do
      def instapay_variance_cents
        statement_instapay_cents - expected_instapay_cents
      end

      def vodafone_cash_variance_cents
        statement_vodafone_cash_cents - expected_vodafone_cash_cents
      end
    end

    def self.call(date:, day_close: nil, location: nil)
      new(date: date, day_close: day_close, location: location).call
    end

    def initialize(date:, day_close: nil, location: nil)
      @date = date
      @day_close = day_close
      @location = location
    end

    def call
      sessions = CashDrawerSession.where(session_date: @date).includes(:user, :location).order(:created_at)
      sessions = sessions.where(location_id: @location.id) if @location
      rows = sessions.map { |session| row_for(session) }

      Summary.new(
        date: @date,
        rows: rows,
        expected_instapay_cents: rows.sum(&:instapay_cents),
        expected_vodafone_cash_cents: rows.sum(&:vodafone_cash_cents),
        statement_instapay_cents: @day_close&.instapay_statement_cents.to_i,
        statement_vodafone_cash_cents: @day_close&.vodafone_cash_statement_cents.to_i,
        day_close: @day_close
      )
    end

    private

    def row_for(session)
      summary = SessionSalesSummary.for_session(session)
      Row.new(
        session: session,
        user: session.user,
        instapay_cents: summary.instapay_cents,
        vodafone_cash_cents: summary.vodafone_cash_cents,
        status: session.status
      )
    end
  end
end
