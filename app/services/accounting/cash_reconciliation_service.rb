# frozen_string_literal: true

module Accounting
  class CashReconciliationService
    VARIANCE_ALERT_THRESHOLD_CENTS = 10_000

    def initialize(session)
      @session = session
    end

    def compute_expected!
      expected = sales_summary.expected_cash_cents
      @session.update!(expected_cash_cents: expected)
      expected
    end

    def sales_summary
      @sales_summary ||= SessionSalesSummary.for_session(@session)
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
          expected: expected,
          instapay_cents: sales_summary.instapay_cents,
          vodafone_cash_cents: sales_summary.vodafone_cash_cents
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
  end
end
