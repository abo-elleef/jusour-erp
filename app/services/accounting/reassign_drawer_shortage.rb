# frozen_string_literal: true

module Accounting
  # Moves a drawer's shortage from the staff member carrying it to someone else.
  #
  # Used by the accountant reviewing the day: the drawer closed short, the
  # voucher went to the drawer's cashier, but someone else handled that cash.
  # The voucher is voided and a new one issued to the new person (never edited
  # in place: it already moved a staff balance and wrote a journal entry). The
  # drawer remembers the new person, so waiving, un-waiving or a count
  # correction later keeps the charge on them. Each move is kept as a
  # DrawerShortageReassignment, with the reason, for the shortage moves report.
  #
  # Refused once either person's payroll month for that day is finalized: the
  # move would change a month already settled. Settle it with a plain voucher.
  class ReassignDrawerShortage
    Result = Struct.new(:success?, :reassignment, :error, keyword_init: true)

    VOID_REASON = "drawer_shortage_reassigned"

    def self.call(session:, to_user:, by:, reason:)
      new(session: session, to_user: to_user, by: by, reason: reason).call
    end

    def initialize(session:, to_user:, by:, reason:)
      @session = session
      @to_user = to_user
      @by = by
      @reason = reason.to_s.strip
    end

    def call
      return failure(:reason_required) if @reason.blank?
      return failure(:no_voucher) unless movable?
      return failure(:invalid_user) unless @to_user&.active? && @to_user.company_id == @session.company_id

      CashDrawerSession.transaction do
        @session.lock!
        return failure(:no_voucher) unless movable?

        from_user = @session.shortage_bearer
        return failure(:same_user) if from_user.id == @to_user.id
        return failure(:payroll_finalized) if payroll_finalized?(from_user, @to_user)

        old_voucher = @session.shortage_voucher
        # Back to the drawer's own cashier: nothing to remember on the drawer.
        @session.update_columns(shortage_charged_to_id: (@to_user.id unless @to_user.id == @session.user_id))
        ::Accounting::DrawerVarianceDocuments.sync!(@session, by: @by)
        new_voucher = @session.reload.shortage_voucher
        old_voucher.reload.update_columns(voided_reason: VOID_REASON, replaced_by_id: new_voucher&.id)

        reassignment = DrawerShortageReassignment.create!(
          company: @session.company,
          cash_drawer_session: @session,
          from_user: from_user,
          to_user: @to_user,
          reassigned_by: @by,
          old_voucher: old_voucher,
          new_voucher: new_voucher,
          amount_cents: old_voucher.amount_cents,
          reason: @reason
        )

        AuditLogEntry.record!(
          action: "cash_drawer.shortage_reassigned",
          record: @session,
          user: @by,
          changes_snapshot: {
            from_user_id: from_user.id, to_user_id: @to_user.id,
            amount_cents: old_voucher.amount_cents, reason: @reason,
            old_voucher_id: old_voucher.id, new_voucher_id: new_voucher&.id
          }
        )

        notify(from_user, "drawer_shortage_moved_off_you", other: @to_user, reassignment: reassignment)
        notify(@to_user, "drawer_shortage_moved_to_you", other: from_user, reassignment: reassignment)

        Result.new(success?: true, reassignment: reassignment)
      end
    end

    private

    # Only a live shortage voucher can move: a waived shortage is a company
    # expense and has nobody to move it from.
    def movable?
      @session.status == "reconciled" && @session.short? && !@session.shortage_waived? &&
        @session.shortage_voucher.present? && !@session.shortage_voucher.voided?
    end

    def payroll_finalized?(*users)
      PayrollSnapshot.for_month(@session.session_date).where(user_id: users.map(&:id)).exists?
    end

    def notify(user, key, other:, reassignment:)
      Notification.create!(
        recipient: user,
        company: @session.company,
        notification_type: "accounting",
        params: {
          message_key: key,
          message_params: {
            variance_cents: reassignment.amount_cents,
            name: other.name,
            session_date: @session.session_date.iso8601,
            reason: @reason
          }
        }
      )
    end

    def failure(error)
      Result.new(success?: false, error: error)
    end
  end
end
