# frozen_string_literal: true

module Admin
  module Users
    class PayrollSnapshotsController < BaseController
      before_action :set_user

      def create
        authorize PayrollSnapshot

        payroll_month = parse_payroll_month
        ::Accounting::FinalizePayrollService.new(
          @user,
          payroll_month,
          finalized_by: current_user,
          treasury: resolve_treasury,
          paid_on: snapshot_params[:paid_on],
          deduction_cents: requested_deduction_cents
        ).call

        redirect_to redirect_path(payroll_month), notice: t("flash.payroll_snapshot.recorded")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to redirect_path(payroll_month), alert: e.record.errors.full_messages.to_sentence
      end

      def destroy
        payroll_month = parse_payroll_month
        snapshot = @user.payroll_snapshots.find_by!(payroll_month: payroll_month)
        authorize snapshot

        # A month from before the ledger started was paid by a backfilled
        # voucher, which only documents its treasury row and can't take it
        # back — so the month can't be undone either.
        if snapshot.payout_voucher&.backfilled?
          return redirect_to redirect_path(payroll_month), alert: t("flash.payroll_snapshot.undo_backfilled")
        end

        ApplicationRecord.transaction do
          # The payout voucher stays in the book, voided — it was a printed
          # document. The treasury removal only matters for months paid
          # before payouts were vouchers.
          snapshot.payout_voucher&.void!(user: current_user, reason: :source_removed)
          ::Accounting::TreasuryLedgerService.remove_source!(snapshot)
          ::Accounting::JournalEntryService.destroy_for_source!(snapshot)
          snapshot.destroy!
        end

        redirect_to redirect_path(payroll_month), notice: t("flash.payroll_snapshot.undone")
      end

      private

      def set_user
        @user = User.find(params[:user_id])
      end

      def snapshot_params
        params.fetch(:payroll_snapshot, {}).permit(:treasury_id, :paid_on, :deduction_pounds)
      end

      # Blank means "use the default" (their plan, or all of it), not zero.
      # Arabic-Indic digits arrive already normalized by arabic-numerals.
      def requested_deduction_cents
        raw = snapshot_params[:deduction_pounds].to_s.strip
        raw.present? ? (raw.to_d * 100).round : nil
      end

      def resolve_treasury
        treasury_id = snapshot_params[:treasury_id]
        return if treasury_id.blank?

        Treasury.active.payable.visible_to(current_user).find(treasury_id)
      end

      def redirect_path(payroll_month)
        month_param = payroll_month.strftime("%Y-%m")

        case params[:return_to]
        when "index"
          admin_users_path
        when "monthly_payroll"
          admin_accounting_monthly_payroll_path(payroll_month: month_param)
        else
          admin_user_path(@user, payroll_month: month_param)
        end
      end
    end
  end
end
