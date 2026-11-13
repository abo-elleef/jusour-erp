# frozen_string_literal: true

module Accounting
  # Undoes a drawer close: the count, the variance, the cash it handed to the safe
  # and the digital takings it booked all come back off the books, and the drawer is
  # open again for the cashier to recount.
  #
  # Only within the business day the drawer belongs to. Once the day has moved on,
  # the day's reports and close have already been built on these numbers.
  class ReopenCashDrawer
    Result = Struct.new(:success?, :session, :error, keyword_init: true)

    def self.call(session:, user:, reason:)
      new(session: session, user: user, reason: reason).call
    end

    def initialize(session:, user:, reason:)
      @session = session
      @user = user
      @reason = reason.to_s.strip
    end

    def call
      return failure(:not_closed) if @session.status == "open"
      return failure(:reason_required) if @reason.blank?
      return failure(:day_passed) unless same_business_day?
      return failure(:another_open) if another_open_drawer?

      previous = snapshot

      CashDrawerSession.transaction do
        # The over/short documents go first: the income or voucher is voided and
        # its cash taken back out of the safe before the deposit itself goes.
        ::Accounting::DrawerVarianceDocuments.remove!(@session, by: @user)

        # Treasury lines first: removing them reverses the balances they moved.
        ::Accounting::TreasuryLedgerService.remove_source!(
          @session, kinds: %w[drawer_reconcile drawer_deposit online_payment]
        )
        %i[reconcile deposit online].each do |kind|
          ::Accounting::JournalEntryService.destroy_for_source!(@session, kind: kind)
        end

        @session.update!(
          status: "open",
          counted_cash_cents: nil,
          variance_cents: nil,
          variance_documented: false,
          shortage_waived_at: nil,
          shortage_waived_by_id: nil
        )
        # The chosen safe stays: nothing moves to it until a new count is saved.
        # The expected figure is recomputed from the payments as they stand now.
        ::Accounting::CashReconciliationService.new(@session).compute_expected!

        AuditLogEntry.record!(
          action: "cash_drawer.reopened",
          record: @session,
          user: @user,
          changes_snapshot: previous.merge(reason: @reason)
        )
      end

      Result.new(success?: true, session: @session)
    end

    private

    def same_business_day?
      @session.session_date == BusinessDay.today(location: @session.location)
    end

    # The cashier works one drawer per branch per day; a second open one would leave
    # two drawers each claiming the same payments.
    def another_open_drawer?
      CashDrawerSession.open
                       .where(user_id: @session.user_id, location_id: @session.location_id,
                              session_date: @session.session_date)
                       .where.not(id: @session.id)
                       .exists?
    end

    def snapshot
      {
        status: @session.status,
        counted: @session.counted_cash_cents,
        variance_cents: @session.variance_cents,
        deposit_treasury_id: @session.deposit_treasury_id,
        deposit_cents: @session.deposit_cents
      }
    end

    def failure(error)
      Result.new(success?: false, session: @session, error: error)
    end
  end
end
