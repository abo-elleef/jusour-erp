# frozen_string_literal: true

module Admin
  module Accounting
    class CashDrawerController < BaseController
      before_action :set_session, only: %i[count reconcile]

      def index
        @date = params[:date]&.to_date || BusinessDay.today
        @sessions = CashDrawerSession.where(session_date: @date).includes(:user, :treasury).order(:shift)
        @drawer_treasuries = Treasury.active.cash_drawers.ordered
        @cashiers = User.active.includes(:assigned_treasury).order(:name)
        @default_user = current_user
        @default_treasury_id = current_user.assigned_treasury_id ||
          Treasury.default_treasury&.id ||
          @drawer_treasuries.first&.id
      end

      def open_session
        user = User.active.find(params[:user_id].presence || current_user.id)
        treasury = resolve_open_treasury(user)
        @session = CashDrawerSession.create!(
          user: user,
          treasury: treasury,
          session_date: BusinessDay.today,
          shift: params[:shift],
          opening_float_cents: (params[:opening_float].to_f * 100).to_i,
          status: "open"
        )
        ::Accounting::CashReconciliationService.new(@session).compute_expected!
        ::Accounting::TreasuryLedgerService.sync_drawer_open!(@session)
        redirect_to admin_accounting_cash_drawer_index_path, notice: t("flash.accounting.drawer_opened")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_accounting_cash_drawer_index_path, alert: e.record.errors.full_messages.to_sentence
      rescue ActiveRecord::RecordNotFound
        redirect_to admin_accounting_cash_drawer_index_path, alert: t("flash.accounting.drawer_open_invalid")
      end

      def count
        ::Accounting::CashReconciliationService.new(@session).compute_expected!
      end

      def reconcile
        counted_cents = (params[:counted_cash].to_f * 100).to_i
        ::Accounting::CashReconciliationService.new(@session).reconcile!(counted_cents)
        redirect_to admin_accounting_cash_drawer_index_path,
              notice: t("flash.accounting.drawer_reconciled_to_treasury", treasury: @session.treasury.name)
      end

      private

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
