# frozen_string_literal: true

module Admin
  module Accounting
    class CashDrawerController < BaseController
      before_action :set_session, only: %i[count reconcile]

      def index
        @date = params[:date]&.to_date || Date.current
        @sessions = CashDrawerSession.where(session_date: @date).includes(:user, :treasury).order(:shift)
        @drawer_treasuries = Treasury.active.cash_drawers.ordered
      end

      def open_session
        treasury = Treasury.find(params[:treasury_id])
        @session = CashDrawerSession.create!(
          user: current_user,
          treasury: treasury,
          session_date: Date.current,
          shift: params[:shift],
          opening_float_cents: (params[:opening_float].to_f * 100).to_i,
          status: "open"
        )
        ::Accounting::CashReconciliationService.new(@session).compute_expected!
        ::Accounting::TreasuryLedgerService.sync_drawer_open!(@session)
        redirect_to admin_accounting_cash_drawer_index_path, notice: t("flash.accounting.drawer_opened")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_accounting_cash_drawer_index_path, alert: e.record.errors.full_messages.to_sentence
      end

      def count
        ::Accounting::CashReconciliationService.new(@session).compute_expected!
      end

      def reconcile
        counted_cents = (params[:counted_cash].to_f * 100).to_i
        ::Accounting::CashReconciliationService.new(@session).reconcile!(counted_cents)
        redirect_to admin_accounting_cash_drawer_index_path, notice: t("flash.accounting.drawer_reconciled")
      end

      private

      def set_session
        @session = CashDrawerSession.find(params[:id])
      end
    end
  end
end
