# frozen_string_literal: true

module Accounting
  class CashReconciliationService
    SHIFT_START_HOURS = { "morning" => 0, "afternoon" => 8, "evening" => 16, "night" => 20 }.freeze
    VARIANCE_ALERT_THRESHOLD_CENTS = 1000

    def initialize(session)
      @session = session
    end

    def self.shift_window_for(session)
      day_start = session.session_date.in_time_zone.beginning_of_day
      offset_hours = SHIFT_START_HOURS.fetch(session.shift, 0)
      shift_start = day_start + offset_hours.hours
      [shift_start, shift_start + 8.hours]
    end

    def compute_expected!
      session_start = @session.created_at
      session_end   = @session.status == "open" ? Time.current : @session.updated_at

      cash_sales = Payment.joins(:order)
        .where(orders: { user_id: @session.user_id })
        .where(payment_method: "cash", status: "completed")
        .where(created_at: session_start..session_end)
        .sum(:amount_cents).to_i

      cash_refunds = Payment.joins(:order)
        .where(orders: { user_id: @session.user_id })
        .where(payment_method: "cash")
        .where(created_at: session_start..session_end)
        .sum(:refunded_amount_cents).to_i

      expected = @session.opening_float_cents + cash_sales - cash_refunds
      @session.update!(expected_cash_cents: expected)
      expected
    end

    def reconcile!(counted_cents)
      expected = @session.expected_cash_cents || compute_expected!
      variance = counted_cents - expected

      @session.update!(
        counted_cash_cents: counted_cents,
        variance_cents: variance,
        status: "reconciled"
      )

      ::Accounting::TreasuryLedgerService.sync_drawer_reconcile!(@session)
      ::Accounting::TreasuryLedgerService.sync_session_online_payments!(@session)

      AuditLogEntry.record!(
        action: "cash_drawer.reconciled",
        record: @session,
        user: @session.user,
        changes_snapshot: {
          variance_cents: variance,
          counted: counted_cents,
          expected: expected
        }
      )

      if variance.abs > VARIANCE_ALERT_THRESHOLD_CENTS
        NotifyService.deliver_to_managers(
          message_key: "cash_variance",
          message_params: {
            variance_cents: variance.abs,
            name: @session.user.name,
            session_date: @session.session_date.iso8601
          }
        )
      end

      @session
    end

    private

    def shift_window
      self.class.shift_window_for(@session)
    end
  end
end
