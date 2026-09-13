# frozen_string_literal: true

module Admin
  module Users
    class PayrollAdvancesController < BaseController
      before_action :set_user
      before_action :set_advance, only: :destroy

      def create
        authorize PayrollAdvance

        paid_on = parse_paid_on
        # The advance date drives the payroll month it is deducted from.
        payroll_month = paid_on.beginning_of_month
        ::Accounting::PayPayrollAdvanceService.new(
          user: @user,
          amount_cents: (advance_params[:amount_pounds].to_f * 100).round,
          treasury: Treasury.find(advance_params[:treasury_id]),
          paid_by: current_user,
          paid_on: paid_on,
          notes: advance_params[:notes]
        ).call

        redirect_to admin_user_path(@user, payroll_show_url_params(payroll_month)),
          notice: t("flash.payroll_advance.paid")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_user_path(@user, payroll_show_url_params(parse_paid_on.beginning_of_month)),
          alert: e.record.errors.full_messages.to_sentence
      end

      def destroy
        authorize @advance
        month = @advance.payroll_month

        ApplicationRecord.transaction do
          ::Accounting::TreasuryLedgerService.remove_source!(@advance)
          # Has to run while the advance still exists — it is addressed by class and
          # id — and cannot be left to the model's `dependent: :destroy`, which only
          # reaches treasury transactions. Editing an advance already clears its
          # entry through `sync_payroll_advance!`; deleting one did not, so every
          # deletion left an entry behind for a payment that no longer existed and
          # the P&L went on counting it.
          ::Accounting::JournalEntryService.destroy_for_source!(@advance)
          @advance.destroy!
        end

        redirect_to admin_user_path(@user, payroll_show_url_params(month)),
          notice: t("flash.payroll_advance.removed")
      rescue ArgumentError => e
        # Raised when the entry has already been reversed: deleting it would strip
        # the reversal of what it reverses. Say so instead of returning a 500.
        redirect_to admin_user_path(@user, payroll_show_url_params(month)),
          alert: e.message
      end

      private

      def set_user
        @user = User.find(params[:user_id])
      end

      def set_advance
        @advance = @user.payroll_advances.find(params[:id])
      end

      def parse_paid_on
        advance_params[:paid_on].present? ? Date.parse(advance_params[:paid_on]) : Date.current
      rescue ArgumentError
        Date.current
      end

      def advance_params
        params.require(:payroll_advance).permit(:amount_pounds, :treasury_id, :paid_on, :notes)
      end

      def payroll_show_url_params(month)
        {
          payroll_month: month.to_date.beginning_of_month.strftime("%Y-%m"),
          payroll_sort: params[:payroll_sort].presence,
          payroll_direction: params[:payroll_direction].presence
        }.compact
      end
    end
  end
end
