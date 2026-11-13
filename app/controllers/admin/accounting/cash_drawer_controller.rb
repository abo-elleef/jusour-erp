# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class CashDrawerController < BaseController
      before_action :set_session, only: %i[show count reconcile payments attach_payments print_slip reopen
                                                 waive_shortage unwaive_shortage]
      helper_method :print_mode?

      def index
        @locations = Location.active.branches.ordered
        # Blank means every branch — the whole business day in one view, which is
        # the question asked at day close. A branch is a narrowing, not the default.
        @location = @locations.find { |l| l.id == params[:location_id] }
        @date = params[:date]&.to_date || BusinessDay.today(location: @location)
        @drawer_treasuries = Treasury.active.cash_drawers.ordered
        # Filtering by drawer answers "what did this till do today" across the
        # cashiers who shared it, which is a different question from "what did this
        # branch do" and the one a manager asks when a till is short.
        @treasury = @drawer_treasuries.find { |t| t.id == params[:treasury_id] }
        @rows, @totals = ::Accounting::DrawerDayReport.call(
          date: @date, location: @location, treasury: @treasury
        )
        @sessions = @rows.map(&:session)
        @cashiers = User.active.includes(:assigned_treasury).order(:name)
        @default_user = current_user
        @default_treasury_id = current_user.assigned_treasury_id ||
          Treasury.default_treasury&.id ||
          @drawer_treasuries.first&.id

        respond_to do |format|
          format.html
          format.csv do
            send_data "\uFEFF#{day_csv}", filename: "cash-drawer-#{@date}.csv", type: "text/csv; charset=utf-8"
          end
        end
      end

      # Read-only: what this drawer took, row by row, so its figures can be traced to
      # the orders behind them. Nothing here recomputes or saves anything.
      def show
        authorize @session, :show?
        calculator = ::Accounting::SessionSalesSummary.new(@session)
        @summary = calculator.call
        @payments = calculator.payments.to_a
        @invoices = calculator.invoices.to_a
        @attached = attach_history(@payments)
        @counted_in_totals = @payments.select { |p| ::Accounting::SessionSalesSummary::KEPT_STATUSES.include?(p.status) }
                                      .group_by(&:payment_method)
                                      .transform_values { |ps| ps.sum { |p| p.amount_cents - p.refunded_amount_cents } }
        @refunded_cents = @payments.sum(&:refunded_amount_cents)
      end

      def open_session
        user = User.active.find(params[:user_id].presence || current_user.id)
        treasury = resolve_open_treasury(user)
        location = Location.active.branches.find(params[:location_id])
        @session = CashDrawerSession.create!(
          user: user,
          treasury: treasury,
          location: location,
          session_date: BusinessDay.today(location: location),
          opening_float_cents: (params[:opening_float].to_f * 100).to_i,
          float_source_treasury: Treasury.float_source,
          status: "open"
        )
        ::Accounting::CashReconciliationService.new(@session).compute_expected!
        ::Accounting::TreasuryLedgerService.sync_drawer_open!(@session)
        redirect_to admin_accounting_cash_drawer_index_path(date: @session.session_date, location_id: location.id),
              notice: t("flash.accounting.drawer_opened")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_accounting_cash_drawer_index_path, alert: e.record.errors.full_messages.to_sentence
      rescue ActiveRecord::RecordNotFound
        redirect_to admin_accounting_cash_drawer_index_path, alert: t("flash.accounting.drawer_open_invalid")
      end

      def count
        service = ::Accounting::CashReconciliationService.new(@session)
        service.compute_expected!
        @sales_summary = service.sales_summary
      end

      def reconcile
        counted_cents = (params[:counted_cash].to_f * 100).to_i
        ::Accounting::CashReconciliationService.new(@session).reconcile!(counted_cents, by: current_user)
        # No register is known here, so it goes to the branch for whichever is open.
        Printing::PrintDrawerCloseService.call(session: @session.reload)
        redirect_to admin_accounting_cash_drawer_index_path,
              notice: t("flash.accounting.drawer_reconciled_to_treasury", treasury: @session.treasury.name)
      end

      # Reprint the closing slip. Printed at the branch (on an open register's
      # printer), not in the browser that asked.
      def print_slip
        authorize @session, :print_slip?
        Printing::PrintDrawerCloseService.call(session: @session)
        redirect_to admin_accounting_cash_drawer_path(@session), notice: t("flash.accounting.drawer_slip_queued")
      rescue Pundit::NotAuthorizedError
        redirect_to admin_accounting_cash_drawer_path(@session), alert: t("flash.accounting.drawer_slip_unavailable")
      end

      # Undo a close, same business day only. Owner / super manager, with a reason.
      # A manager takes a shortage off the cashier: the voucher to them is voided
      # and the same amount becomes a company expense, paid from the same safe —
      # the cash is still missing, so the safe must stay down by it.
      def waive_shortage
        authorize @session, :waive_shortage?
        change_shortage_waiver!(waived: true)
        redirect_to admin_accounting_cash_drawer_path(@session), notice: t("flash.accounting.drawer_shortage_waived")
      rescue Pundit::NotAuthorizedError
        redirect_to admin_accounting_cash_drawer_path(@session), alert: t("flash.accounting.drawer_shortage_waive_failed")
      end

      def unwaive_shortage
        authorize @session, :unwaive_shortage?
        change_shortage_waiver!(waived: false)
        redirect_to admin_accounting_cash_drawer_path(@session), notice: t("flash.accounting.drawer_shortage_unwaived")
      rescue Pundit::NotAuthorizedError
        redirect_to admin_accounting_cash_drawer_path(@session), alert: t("flash.accounting.drawer_shortage_waive_failed")
      end

      def reopen
        authorize @session, :reopen?
        result = ::Accounting::ReopenCashDrawer.call(
          session: @session, user: current_user, reason: params[:reason]
        )

        if result.success?
          redirect_to admin_accounting_cash_drawer_path(@session), notice: t("flash.accounting.drawer_reopened")
        else
          redirect_to admin_accounting_cash_drawer_path(@session),
                      alert: t("flash.accounting.drawer_reopen_#{result.error}")
        end
      rescue Pundit::NotAuthorizedError
        redirect_to admin_accounting_cash_drawer_path(@session), alert: t("flash.accounting.drawer_reopen_forbidden")
      end

      # Payments taken before this drawer was opened (so they belong to no drawer),
      # for an admin to pull into it.
      def payments
        @attacher = ::Accounting::DrawerPaymentAttacher.new(@session)
        @payments = @attacher.candidates
      end

      def attach_payments
        result = ::Accounting::DrawerPaymentAttacher.attach!(
          session: @session, payment_ids: params[:payment_ids], by: current_user
        )

        if result.ok?
          redirect_to payments_admin_accounting_cash_drawer_path(@session),
                      notice: t("flash.accounting.drawer_payments_attached", count: result.attached.size)
        else
          redirect_to payments_admin_accounting_cash_drawer_path(@session),
                      alert: t("flash.accounting.drawer_attach_#{result.error}")
        end
      end

      private

      # ?print=1 opens a clean copy (no filters, forms or row actions) and the
      # print dialog, like the ledger reports.
      def print_mode?
        params[:print].present?
      end

      # The same rows and totals the table shows, so it follows the same filters.
      def day_csv
        CSV.generate do |csv|
          csv << [t("accounting.cash_drawer.title"), @date.to_s,
                  @location&.name || t("accounting.cash_drawer.all_locations"),
                  @treasury&.name || t("accounting.cash_drawer.all_drawers")]
          csv << [t("admin.locations.type_branch"), t("accounting.cash_drawer.cashier"), t("accounting.shared.treasury"),
                  t("accounting.cash_drawer.opened_at"), t("accounting.cash_drawer.status"),
                  t("payment.methods.cash"), t("payment.methods.instapay"), t("payment.methods.vodafone_cash"),
                  t("accounting.cash_drawer.expected"), t("accounting.cash_drawer.counted"),
                  t("accounting.cash_drawer.variance"), t("accounting.cash_drawer.banked_to"),
                  t("accounting.cash_drawer.banked")]
          @rows.each do |row|
            session = row.session
            csv << [session.location&.name, session.user.name, session.treasury.name,
                    I18n.l(session.created_at, format: :short_time), helpers.accounting_drawer_status(session.status),
                    csv_amount(row.cash_cents), csv_amount(row.instapay_cents), csv_amount(row.vodafone_cash_cents),
                    csv_amount(session.expected_cash_cents), csv_amount(session.counted_cash_cents),
                    csv_amount(session.variance_cents),
                    (row.deposit_treasury.name if row.deposit_treasury && row.deposited_cents.positive?),
                    csv_amount(row.deposited_cents)]
          end
          csv << [t("accounting.cash_drawer.table_total"), nil, nil, nil, nil,
                  csv_amount(@totals.cash_cents), csv_amount(@totals.instapay_cents),
                  csv_amount(@totals.vodafone_cash_cents), csv_amount(@totals.expected_cents),
                  csv_amount(@totals.counted_cents), csv_amount(@totals.variance_cents), nil,
                  csv_amount(@totals.deposited_cents)]
        end
      end

      # Blank, not 0.00, for a drawer nobody has counted yet — same as the em dash on screen.
      def csv_amount(cents)
        cents.nil? ? nil : format("%.2f", cents.to_d / 100)
      end

      # payment id => the audit entry that moved it into this drawer, if one did.
      def attach_history(payments)
        entries = AuditLogEntry.includes(:user)
                               .where(action: "payment.attached_to_drawer", record_type: "Payment",
                                      record_id: payments.map(&:id))
                               .order(:created_at)
        entries.select { |e| e.changes_snapshot["cash_drawer_session_id"] == @session.id }
               .index_by(&:record_id)
      end

      def change_shortage_waiver!(waived:)
        CashDrawerSession.transaction do
          @session.update_columns(
            shortage_waived_at: (Time.current if waived),
            shortage_waived_by_id: (current_user.id if waived)
          )
          ::Accounting::DrawerVarianceDocuments.sync!(@session, by: current_user)
          AuditLogEntry.record!(
            action: waived ? "cash_drawer.shortage_waived" : "cash_drawer.shortage_unwaived",
            record: @session,
            user: current_user,
            changes_snapshot: { variance_cents: @session.variance_cents }
          )
        end
      end

      def set_session
        @session = CashDrawerSession.find(params[:id])
      end

      def resolve_open_treasury(user)
        if params[:treasury_id].present?
          Treasury.active.cash_drawers.find(params[:treasury_id])
        elsif user.assigned_treasury&.active? && user.assigned_treasury.treasury_type == "cash_drawer"
          user.assigned_treasury
        else
          raise ActiveRecord::RecordNotFound
        end
      end
    end
  end
end
