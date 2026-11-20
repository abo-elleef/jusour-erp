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

    # `by` is whoever closed the drawer — the cashier at the till, or a manager
    # from the admin — and is recorded on the over/short documents.
    #
    # In the company's default (documented) mode the books take what the drawer
    # should have held (expected); the gap to the count becomes its own document
    # (Accounting::DrawerVarianceDocuments), so the safe still ends up holding
    # exactly what was counted. In simple mode the books take the count and the
    # gap is only reported.
    def reconcile!(counted_cents, by: nil)
      expected = @session.expected_cash_cents || compute_expected!
      variance = counted_cents - expected
      # A count correction keeps the mode the drawer was first closed under, so
      # changing the company setting never rewrites a closed drawer's books.
      documented = @session.status == "reconciled" ? @session.variance_documented? : Setting.document_drawer_variance?
      # Likewise a correction keeps when and by whom the drawer was first closed.
      first_close = @session.closed_at.nil?

      CashDrawerSession.transaction do
        @session.update!(
          counted_cash_cents: counted_cents,
          variance_cents: variance,
          variance_documented: documented,
          status: "reconciled",
          closed_at: first_close ? Time.current : @session.closed_at,
          closed_by_id: first_close ? (by || @session.user)&.id : @session.closed_by_id
        )

        ::Accounting::TreasuryLedgerService.sync_drawer_reconcile!(@session)
        ::Accounting::TreasuryLedgerService.sync_session_online_payments!(@session)
        # Last, so the drawer is banked only after the takings are in it.
        ::Accounting::TreasuryLedgerService.sync_drawer_deposit!(@session)
        ::Accounting::DrawerVarianceDocuments.sync!(@session, by: by)
      end

      AuditLogEntry.record!(
        action: "cash_drawer.reconciled",
        record: @session,
        # Whoever saved the count — the cashier, or a manager from admin.
        user: by || @session.user,
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
