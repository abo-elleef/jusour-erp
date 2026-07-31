# frozen_string_literal: true

module Pos
  class ShiftsController < ApplicationController
    include PosLocationScoped

    layout "pos"

    before_action :require_pos_access!
    before_action :set_open_session, only: %i[count reconcile]

    def show
      @open_session = current_user.open_cash_drawer_session
      @tab = params[:tab].presence_in(%w[shift orders]) || (@open_session ? "orders" : "shift")
      @today_session = current_user.todays_cash_drawer_session
      @assigned_treasury = current_user.assigned_treasury
      @unpaid_orders_count = unpaid_orders_for(current_user).size
      @has_draft_cart = draft_order_for(current_user).present?
      load_shift_orders if @tab == "orders"
    end

    def open_drawer
      authorize CashDrawerSession, :open_drawer?

      if current_user.open_cash_drawer_session
        return redirect_to pos_shift_path, alert: t("flash.pos.shift.drawer_already_open")
      end

      treasury = current_user.assigned_treasury
      unless treasury&.active? && treasury.treasury_type == "cash_drawer"
        return redirect_to pos_shift_path, alert: t("flash.pos.shift.no_assigned_treasury")
      end

      session = CashDrawerSession.create!(
        user: current_user,
        treasury: treasury,
        session_date: BusinessDay.today,
        opening_float_cents: (params[:opening_float].to_f * 100).to_i,
        status: "open"
      )
      ::Accounting::CashReconciliationService.new(session).compute_expected!
      ::Accounting::TreasuryLedgerService.sync_drawer_open!(session)
      redirect_to pos_shift_path, notice: t("flash.accounting.drawer_opened")
    rescue ActiveRecord::RecordInvalid => e
      redirect_to pos_shift_path, alert: e.record.errors.full_messages.to_sentence
    end

    def clock_in
      authorize ShiftLog, :clock_in?
      if current_user.clocked_in?
        return redirect_to pos_shift_path, alert: t("flash.accounting.already_clocked_in")
      end

      shift = ShiftLog.create!(
        user: current_user,
        clocked_in_at: Time.current,
        hourly_rate_cents: current_user.hourly_rate_cents,
        status: "active"
      )
      AuditLogEntry.record!(action: "shift.clock_in", record: shift, user: current_user)
      redirect_to pos_shift_path, notice: t("flash.accounting.clocked_in", time: l(Time.current, format: :short_time))
    end

    def count
      authorize @open_session, :count?
      ::Accounting::CashReconciliationService.new(@open_session).compute_expected!
      @requires_manager_pin = false
      @digital_payment_totals = load_digital_payment_totals
      @payment_method_treasury_map = PaymentMethodTreasury::SUPPORTED_METHODS.index_with do |method|
        PaymentMethodTreasury.find_by(payment_method: method)&.treasury
      end
    end

    def reconcile
      authorize @open_session, :reconcile?

      counted_cents = (params[:counted_cash].to_f * 100).to_i
      if counted_cents <= 0
        return redirect_to count_pos_shift_path, alert: t("flash.pos.shift.count_required")
      end

      expected = ::Accounting::CashReconciliationService.new(@open_session).compute_expected!
      variance = counted_cents - expected

      if variance.abs > ::Accounting::CashReconciliationService::VARIANCE_ALERT_THRESHOLD_CENTS &&
         !manager_approved_reconcile?(@open_session)
        @requires_manager_pin = true
        @variance_cents = variance
        @counted_cents = counted_cents
        flash.now[:alert] = t("flash.pos.shift.manager_pin_required")
        return render :count, status: :unprocessable_entity
      end

      ::Accounting::CashReconciliationService.new(@open_session).reconcile!(counted_cents)
      redirect_to pos_shift_path, notice: t("flash.accounting.drawer_reconciled_to_treasury",
            treasury: @open_session.treasury.name)
    end

    def clock_out
      shift = current_user.current_shift
      unless shift
        return redirect_to pos_shift_path, alert: t("flash.pos.shift.not_clocked_in")
      end

      authorize shift, :clock_out?
      ::Accounting::ClockOutService.new(shift, user: current_user).call
      redirect_to pos_shift_path, notice: t("flash.accounting.clocked_out")
    rescue Accounting::ClockOutService::Error => e
      redirect_to pos_shift_path, alert: e.message
    end

    private

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end

    def set_open_session
      @open_session = current_user.open_cash_drawer_session
      return if @open_session

      redirect_to pos_shift_path, alert: t("flash.pos.shift.no_open_drawer")
    end

    def unpaid_orders_for(user)
      Order.awaiting_payment
        .where(user: user)
        .includes(:payments)
        .limit(100)
        .select { |order| order.amount_due_cents.positive? }
    end

    def draft_order_for(user)
      return unless session[:current_order_id]

      Order.find_by(id: session[:current_order_id], status: "draft", user_id: user.id)
    end

    def load_shift_orders
      @shift_time_range = current_user.shift_orders_time_range
      @shift_orders = if @shift_time_range
        start_time, end_time = @shift_time_range
        Order.where(user: current_user)
          .where(created_at: start_time..end_time)
          .includes(:customer, :payments)
          .order(created_at: :desc)
      else
        Order.none
      end
    end

    def load_digital_payment_totals
      session_start = @open_session.created_at
      session_end   = Time.current
      Payment::DIGITAL_WALLET_METHODS.index_with do |method|
        Payment.joins(:order)
          .where(orders: { user_id: @open_session.user_id })
          .where(payment_method: method, status: "completed")
          .where(created_at: session_start..session_end)
          .sum(:amount_cents).to_i
      end
    end

    def manager_approved_reconcile?(drawer_session)
      return true if current_user.admin_access?

      pin = params[:manager_pin].to_s
      return false if pin.blank?

      User.active.where(role: %w[owner manager]).any? { |u| u.authenticate_pin(pin) }
    end
  end
end
