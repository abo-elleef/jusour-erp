# frozen_string_literal: true

module Pos
  class ShiftsController < ApplicationController
    include PosLocationScoped

    layout "pos"

    # The payment-method column shows completed payments only; the filter matches it.
    SHIFT_PAYMENT_STATUS = "completed"

    # Sortable columns of the orders table → SQL columns (fixed strings, never user input).
    # Order numbers are digit strings, so length first makes "10" come after "9".
    SHIFT_ORDER_SORTS = {
      "number" => %w[LENGTH(orders.order_number) orders.order_number],
      "time" => %w[orders.created_at],
      "type" => %w[orders.order_type],
      "status" => %w[orders.status],
      "delivery_fee" => %w[orders.delivery_fee_cents],
      "total" => %w[orders.total_cents]
    }.freeze

    before_action :require_pos_access!
    before_action :set_open_session, only: %i[count reconcile]
    # Both of these end the shift, and neither may happen over an order that was
    # never finished. Checked on the writes rather than on `count`, so a cashier can
    # still see what the drawer should hold while they clear the backlog.
    before_action :block_open_orders!, only: %i[reconcile clock_out]

    def show
      @open_session = current_user.open_cash_drawer_session(location: @pos_location)
      @tab = params[:tab].presence_in(%w[shift orders]) || (@open_session ? "orders" : "shift")
      @today_session = current_user.todays_cash_drawer_session(location: @pos_location)
      @assigned_treasury = current_user.assigned_treasury
      @business_day = BusinessDay.today(location: @pos_location)
      unpaid_orders = unpaid_orders_for(current_user)
      @unpaid_orders_count = unpaid_orders.size
      @unpaid_orders_due_cents = unpaid_orders.sum(&:amount_due_cents)
      @unfinalized_orders_count = unfinalized_orders_for(current_user).count
      @has_draft_cart = draft_order_for(current_user).present?
      if @today_session
        @today_sales_summary = ::Accounting::SessionSalesSummary.for_session(@today_session)
      end
      load_shift_orders if @tab == "orders"
    end

    def open_drawer
      authorize CashDrawerSession, :open_drawer?

      if @pos_location.blank?
        return redirect_to pos_shift_path, alert: t("flash.pos.shift.select_branch_first")
      end

      if current_user.open_cash_drawer_session(location: @pos_location)
        return redirect_to pos_shift_path, alert: t("flash.pos.shift.drawer_already_open")
      end

      treasury = current_user.assigned_treasury
      unless treasury&.active? && treasury.treasury_type == "cash_drawer"
        return redirect_to pos_shift_path, alert: t("flash.pos.shift.no_assigned_treasury")
      end

      session = CashDrawerSession.create!(
        user: current_user,
        treasury: treasury,
        location: @pos_location,
        session_date: BusinessDay.today(location: @pos_location),
        opening_float_cents: (params[:opening_float].to_f * 100).to_i,
        float_source_treasury: Treasury.float_source,
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
      service = ::Accounting::CashReconciliationService.new(@open_session)
      service.compute_expected!
      @sales_summary = service.sales_summary
      @requires_manager_pin = false
      load_deposit_destination
    end

    def reconcile
      authorize @open_session, :reconcile?

      counted_cents = (params[:counted_cash].to_f * 100).to_i

      assign_deposit_treasury!

      service = ::Accounting::CashReconciliationService.new(@open_session)
      expected = service.compute_expected!

      # An empty count is only believable when the drawer should be empty too (no
      # float, no cash sales). Otherwise it is almost certainly a form left blank.
      if counted_cents <= 0 && expected.positive?
        return redirect_to count_pos_shift_path, alert: t("flash.pos.shift.count_required")
      end
      variance = counted_cents - expected

      if variance.abs > ::Accounting::CashReconciliationService::VARIANCE_ALERT_THRESHOLD_CENTS &&
         !manager_approved_reconcile?(@open_session)
        @requires_manager_pin = true
        @variance_cents = variance
        @counted_cents = counted_cents
        @sales_summary = service.sales_summary
        load_deposit_destination
        flash.now[:alert] = t("flash.pos.shift.manager_pin_required")
        return render :count, status: :unprocessable_entity
      end

      service.reconcile!(counted_cents, by: current_user)

      # The slip the cashier and the shift manager sign. Never blocks closing.
      Printing::PrintDrawerCloseService.call(session: @open_session.reload, workstation: @pos_workstation)

      deposit = @open_session.reload.deposit_treasury
      notice = if deposit
        t("flash.accounting.drawer_banked_to_treasury", treasury: deposit.name)
      else
        t("flash.accounting.drawer_reconciled_to_treasury", treasury: @open_session.treasury.name)
      end
      redirect_to pos_shift_path, notice: notice
    end

    # Reprint the closing slip of a drawer that has been counted. The cashier's own,
    # or any when an admin asks.
    def print_closing_slip
      drawer = CashDrawerSession.find(params[:session_id])
      authorize drawer, :print_slip?

      Printing::PrintDrawerCloseService.call(session: drawer, workstation: @pos_workstation)
      redirect_to pos_shift_path, notice: t("flash.pos.shift.closing_slip_queued")
    rescue Pundit::NotAuthorizedError
      redirect_to pos_shift_path, alert: t("flash.pos.shift.closing_slip_unavailable")
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
      @open_session = current_user.open_cash_drawer_session(location: @pos_location)
      return if @open_session

      redirect_to pos_shift_path, alert: t("flash.pos.shift.no_open_drawer")
    end

    # The branch decides where its takings go, not whoever happens to be closing.
    # The cashier is shown the destination; they do not choose it.
    def load_deposit_destination
      location = @open_session.location
      @deposit_treasury = location&.deposit_treasury_or_default
      @deposit_is_fallback = @deposit_treasury.present? && !location&.deposit_treasury_configured?
    end

    def assign_deposit_treasury!
      load_deposit_destination
      @open_session.update!(deposit_treasury: @deposit_treasury)
    end

    # An order is done with when it is finished and paid. Unfinished ones go to
    # the shift's orders tab; finished-but-unpaid ones to Collect Payment, which
    # lists only this cashier's orders — nobody else will collect them.
    def block_open_orders!
      count = unfinalized_orders_for(current_user).count
      if count.positive?
        return redirect_to pos_shift_path(tab: "orders"),
                           alert: t("flash.pos.shift.finish_orders_first", count: count)
      end

      unpaid = current_user.unpaid_shift_orders(location: @pos_location).size
      return if unpaid.zero?

      redirect_to pos_orders_path, alert: t("flash.pos.shift.collect_payment_first", count: unpaid)
    end

    def unfinalized_orders_for(user)
      user.unfinalized_shift_orders(location: @pos_location)
    end

    def unpaid_orders_for(user)
      # Same definition as Collect Payment, so the shift warning and the screen it
      # sends the cashier to can never disagree about what is still owed.
      Order.not_fully_paid
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
      # The cashier sees their current drawer session and nothing older: no order
      # is rung without an open drawer, so the session is the shift. Orders left
      # open from an earlier session are the admin's to handle, not the cashier's.
      @shift_drawer = current_user.current_drawer_session(location: @pos_location)
      unfinalized = unfinalized_orders_for(current_user)
      @open_orders_count = unfinalized.count
      @paid_open_orders_count = unfinalized.includes(:payments).count(&:fully_paid?)

      session_orders = @shift_drawer ? @shift_drawer.orders : Order.none
      @shift_time_range = @shift_drawer && [@shift_drawer.order_window.begin, @shift_drawer.order_window.end]

      # One list, two views: "open" is what the cashier came here to clear and is
      # the default whenever anything is open; "all" is the session's history.
      @filter = params[:filter].presence_in(%w[open all]) || (@open_orders_count.positive? ? "open" : "all")
      shown = Order.where(id: (@filter == "open" ? unfinalized : session_orders).select(:id))

      # Methods actually taken in this list, so the dropdown never offers an empty choice.
      @payment_method_options = Payment.where(order_id: shown.select(:id), status: SHIFT_PAYMENT_STATUS)
        .distinct.pluck(:payment_method)
        .sort_by { |method| Payment::METHODS.index(method) || Payment::METHODS.size }

      @order_type_filter = params[:order_type].presence_in(Order::ORDER_TYPES)
      @payment_method_filter = params[:payment_method].presence_in(Payment::METHODS)
      shown = shown.where(order_type: @order_type_filter) if @order_type_filter
      if @payment_method_filter
        shown = shown.where(id: Payment.where(payment_method: @payment_method_filter, status: SHIFT_PAYMENT_STATUS)
                                       .select(:order_id))
      end

      @sort = params[:sort].presence_in(SHIFT_ORDER_SORTS.keys) || "time"
      @direction = params[:dir] == "asc" ? "asc" : "desc"
      @shift_orders = shown.includes(:customer, :payments)
        .order(Arel.sql(SHIFT_ORDER_SORTS.fetch(@sort).map { |column| "#{column} #{@direction}" }.join(", ")))
        .order(created_at: :desc)
      # A cancelled order earned nothing, so it is listed but not added up.
      filtered_live = shown.where.not(status: "cancelled")
      @shift_orders_total_cents = filtered_live.sum(:total_cents)
      @shift_orders_total_count = filtered_live.count
      @shift_orders_delivery_fee_cents = filtered_live.sum(:delivery_fee_cents)
      @all_orders_count = session_orders.count
    end

    # Keeps the order-type / payment-method filters and the sort when switching Open ↔ All.
    def shift_orders_filter_params
      { order_type: @order_type_filter, payment_method: @payment_method_filter,
        sort: params[:sort].presence && @sort, dir: params[:dir].presence && @direction }.compact
    end
    helper_method :shift_orders_filter_params

    def manager_approved_reconcile?(drawer_session)
      return true if current_user.admin_access?

      pin = params[:manager_pin].to_s
      return false if pin.blank?

      User.active.where(role: %w[owner manager]).any? { |u| u.authenticate_pin(pin) }
    end
  end
end
