# frozen_string_literal: true

module Accounting
  # Puts payments that were taken before any drawer was open into one that is.
  #
  # A cashier can ring up and take payment on orders before opening their drawer for
  # the day. Those payments carry no cash_drawer_session_id, and because they
  # pre-date the drawer the summary's time-window fallback does not pick them up
  # either, so the drawer's expected cash comes up short of what is physically in it.
  #
  # Only an open drawer can receive them: a reconciled one has already been counted,
  # banked and posted to the ledger, and attaching afterwards would change a closed
  # figure without moving the money.
  class DrawerPaymentAttacher
    # Cash only: it is the money that physically sits in the till. Instapay and
    # Vodafone Cash never pass through the drawer, so attaching them gains nothing.
    METHODS = %w[cash].freeze
    # How far back orphaned payments are looked for — a day boundary can sit hours
    # off the calendar date, so the window is wider than one day and the business
    # day itself does the filtering.
    LOOKBACK = 3.days

    Result = Struct.new(:attached, :error, keyword_init: true) do
      def ok? = error.nil?
    end

    def self.candidates(session)
      new(session).candidates
    end

    def self.attach!(session:, payment_ids:, by:)
      new(session).attach!(payment_ids: payment_ids, by: by)
    end

    def initialize(session)
      @session = session
    end

    def attachable?
      @session.status == "open"
    end

    # Completed, unassigned payments on orders from this branch that fall inside the
    # drawer's business day.
    def candidates
      return Payment.none unless attachable?

      ids = base_scope.select { |payment| on_session_day?(payment) }.map(&:id)
      Payment.where(id: ids).includes(:processed_by_user, order: :user).order(:created_at)
    end

    def attach!(payment_ids:, by:)
      return Result.new(error: :not_open) unless attachable?

      selected = candidates.where(id: Array(payment_ids))
      return Result.new(error: :nothing_selected) if selected.empty?

      attached = nil
      Payment.transaction do
        attached = selected.to_a
        attached.each do |payment|
          payment.update!(cash_drawer_session: @session)
          AuditLogEntry.record!(
            action: "payment.attached_to_drawer",
            record: payment,
            user: by,
            changes_snapshot: { cash_drawer_session_id: @session.id, amount_cents: payment.amount_cents }
          )
        end
      end

      ::Accounting::CashReconciliationService.new(@session).compute_expected!
      Result.new(attached: attached)
    end

    private

    def base_scope
      Payment.joins(:order)
             .where(status: "completed", cash_drawer_session_id: nil, payment_method: METHODS)
             .where(orders: { location_id: @session.location_id })
             .where(created_at: (@session.session_date.beginning_of_day - LOOKBACK)..Time.current)
             .includes(:order)
    end

    def on_session_day?(payment)
      BusinessDay.for(payment.created_at, location: @session.location) == @session.session_date
    end
  end
end
