# frozen_string_literal: true

module Admin
  module Accounting
    class TreasuriesController < BaseController
      before_action :set_treasury, only: %i[show edit update destroy adjust]

      def index
        authorize Treasury
        @q = Treasury.ransack(params[:q])
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @treasuries = @q.result.ordered
        @total_balance_cents = Treasury.active.payable.sum(:balance_cents)
        @supplier_ap_balance_cents = Treasury.active.supplier_ap.sum(:balance_cents)
      end

      def show
        authorize @treasury
        parse_date_range
        @transactions = @treasury.treasury_transactions
          .includes(:user)
          .on_date_range(@start_date, @end_date)
          .recent
          .limit(200)
      end

      def new
        @treasury = Treasury.new(active: true)
        authorize @treasury
      end

      def create
        @treasury = Treasury.new(treasury_params)
        authorize @treasury
        @treasury.balance_cents = @treasury.opening_balance_cents

        if @treasury.save
          clear_other_defaults! if @treasury.is_default?
          redirect_to admin_accounting_treasury_path(@treasury), notice: t("flash.accounting.treasury_created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize @treasury
      end

      def update
        authorize @treasury
        if @treasury.update(treasury_params)
          clear_other_defaults! if @treasury.is_default?
          redirect_to admin_accounting_treasury_path(@treasury), notice: t("flash.accounting.treasury_updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @treasury
        if @treasury.expenses.exists? || @treasury.incomes.exists? ||
           @treasury.cash_drawer_sessions.exists? || @treasury.outgoing_transfers.exists? ||
           @treasury.incoming_transfers.exists?
          redirect_to admin_accounting_treasuries_path, alert: t("flash.accounting.treasury_in_use")
        else
          @treasury.destroy!
          redirect_to admin_accounting_treasuries_path, notice: t("flash.accounting.treasury_removed")
        end
      end

      def adjust
        authorize @treasury, :update?
        amount_cents = (params[:amount_pounds].to_f * 100).round
        if amount_cents.zero?
          redirect_to admin_accounting_treasury_path(@treasury), alert: t("flash.accounting.treasury_adjustment_invalid")
          return
        end

        ::Accounting::TreasuryLedgerService.new.record_adjustment!(
          treasury: @treasury,
          user: current_user,
          amount_cents: amount_cents,
          description: params[:description].presence || t("accounting.treasuries.manual_adjustment"),
          occurred_on: params[:occurred_on]&.to_date || Date.current
        )
        redirect_to admin_accounting_treasury_path(@treasury), notice: t("flash.accounting.treasury_adjusted")
      end

      private

      def set_treasury
        @treasury = Treasury.find(params[:id])
      end

      def treasury_params
        params.require(:treasury).permit(:name, :treasury_type, :opening_balance_pounds, :active, :is_default, :position, :notes)
      end

      def clear_other_defaults!
        Treasury.where.not(id: @treasury.id).where(is_default: true).update_all(is_default: false)
      end
    end
  end
end
