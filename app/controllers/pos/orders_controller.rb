# frozen_string_literal: true

module Pos
  class OrdersController < ApplicationController
    include PosLocationScoped

    layout "pos"

    before_action :require_pos_access!

    def index
      authorize Order, :index_for_payment?

      @filter_type = params[:order_type].presence
      @filter_type = nil if @filter_type == "all"

      @orders = outstanding_orders
    end

    # Settles everything currently listed, in cash, in one press. Scoped to the
    # same filters as the page: what the cashier is looking at is what they are
    # collecting, which is the only version of this they can check before pressing.
    def collect_all_cash
      authorize Order, :collect_all_cash?

      unless current_user.open_cash_drawer_session(location: @pos_location)
        return redirect_to pos_orders_path(order_type: @filter_type),
                           alert: t("flash.pos.shift.no_open_drawer")
      end

      result = Payments::BulkCashCollectService.call(orders: outstanding_orders, user: current_user)

      if result.any?
        redirect_to pos_orders_path(order_type: @filter_type),
                    notice: t("flash.pos.cash_collected",
                              count: result.settled.size,
                              amount: helpers.format_money(result.collected_cents))
      else
        redirect_to pos_orders_path(order_type: @filter_type),
                    alert: t("flash.pos.nothing_to_collect")
      end
    end

    def sync_offline
      authorize Order, :create?
      payload = params.require(:order).permit(
        :order_id, :tip_cents,
        payments_attributes: %i[payment_method amount_cents]
      )
      result = Orders::SyncOfflineService.call(user: current_user, payload: payload.to_h)

      if result.success?
        render json: {
          success: true,
          order_number: result.order.order_number,
          order_id: result.order.id
        }, status: :created
      else
        render json: { success: false, errors: result.errors }, status: :unprocessable_entity
      end
    end

    def show
      @order = Order.includes(:payments, order_items: [:menu_item, :combo, :order_item_modifiers])
                    .find(params[:id])
      @order.recalculate_totals!
      authorize @order, :show?

      @from_shift = params[:from] == "shift"
      @order_items = @order.order_items.order(:created_at, :id)
      @payments = @order.payments.order(created_at: :desc)

      if @from_shift || @order.amount_due_cents.zero?
        return
      end

      authorize @order, :checkout?
      session[:checkout_order_id] = @order.id
    end

    def resume
      order = Order.find(params[:id])
      authorize order, :show?
      unless order.draft? && order.user == current_user
        authorize order, :resume_table?
      end

      session[:current_order_id] = order.id
      redirect_to pos_path, notice: t("flash.pos.order_resumed")
    end

    def update_fulfillment
      @order = Order.find(params[:id])
      authorize @order, :update?
      raise Pundit::NotAuthorizedError if @order.cancelled? || @order.voided?

      attrs = params.permit(:order_type, :table_number, :delivery_address).to_h
      attrs[:delivery_address] = nil if @order.customer.blank?

      if @order.update(attrs)
        if @order.delivery? && @order.customer.present? && @order.delivery_address.blank?
          addr = @order.customer.default_address
          @order.update!(delivery_address: addr.address) if addr.present?
        end
        redirect_to pos_order_path(@order, from: params[:from]),
                    notice: t("flash.pos.order_updated")
      else
        redirect_to pos_order_path(@order, from: params[:from]),
                    alert: @order.errors.full_messages.to_sentence
      end
    end

    def complete
      @order = Order.find(params[:id])
      authorize @order, :complete?

      if Orders::CompleteService.call(@order)
        # Clearing a table from the board goes back to the board.
        destination = params[:from] == "tables" ? pos_tables_path : pos_order_path(@order, from: params[:from])
        redirect_to destination, notice: t("flash.pos.order_completed")
      else
        redirect_to pos_order_path(@order, from: params[:from]), alert: t("flash.pos.order_not_completable")
      end
    end

    # End of shift: close everything this cashier still has open. Scoped to their
    # own orders — a cashier closing down must not sweep the next register's tickets
    # off the pass.
    def complete_all
      authorize Order, :complete_all?
      complete_and_redirect(open_orders_for(current_user))
    end

    # The safe version of the above: only the open orders whose payment is already
    # fully collected. Unpaid or part-paid ones stay open for Collect Payment.
    def complete_paid
      authorize Order, :complete_all?
      complete_and_redirect(open_orders_for(current_user).includes(:payments).select(&:fully_paid?))
    end

    def complete_and_redirect(orders)
      result = Orders::CompleteService.call_all(orders)

      # Three outcomes, not two. "Nothing was completed" and "there was nothing to
      # complete" are different things, and telling a cashier the second when the
      # first is true sends them looking for orders the page says do not exist.
      if result.completed.any?
        redirect_to pos_shift_path(tab: "orders"), flash: {
          notice: t("flash.pos.orders_completed", count: result.completed.size),
          alert: (t("flash.pos.orders_not_completable", count: result.skipped.size) if result.skipped.any?)
        }.compact
      elsif result.skipped.any?
        redirect_to pos_shift_path(tab: "orders"),
                    alert: t("flash.pos.orders_not_completable", count: result.skipped.size)
      else
        redirect_to pos_shift_path(tab: "orders"), alert: t("flash.pos.no_orders_to_complete")
      end
    end
    private :complete_and_redirect

    def destroy
      @order = Order.find(params[:id])
      authorize @order, :destroy?

      number = @order.order_number
      order_id = @order.id
      AuditLogEntry.record!(action: "order.discard", record: @order, user: current_user)
      @order.destroy!
      session.delete(:current_order_id) if session[:current_order_id] == order_id

      redirect_to pos_shift_path(tab: "orders"),
                  notice: t("flash.pos.order_discarded", number: number)
    end

    def print_receipt
      @order = Order.find(params[:id])
      authorize @order, :show?
      Printing::PrintReceiptService.call(order: @order, manual: true)
      # From the register itself, stay on the register: the cart is still being built.
      destination = params[:from] == "pos" ? pos_path : pos_order_path(@order, from: params[:from])
      redirect_to destination, notice: t("flash.pos.print_queued")
    end

    # Sends the tickets to the kitchen / bar / expo printers ahead of payment.
    # Print-only: the order, its items and its payments are not touched.
    def send_to_kitchen
      @order = Order.find(params[:id])
      authorize @order, :show?
      Printing::DispatchProductionPrintsService.call(order: @order, manual: true)
      destination = params[:from] == "pos" ? pos_path : pos_order_path(@order, from: params[:from])
      redirect_to destination, notice: t("flash.pos.kitchen_queued")
    end

    def print_all
      @order = Order.find(params[:id])
      authorize @order, :show?
      Printing::PrintReceiptService.call(order: @order, manual: true)
      Printing::DispatchProductionPrintsService.call(order: @order, manual: true)
      redirect_to pos_order_path(@order, from: params[:from]), notice: t("flash.pos.print_all_queued")
    end

    private

    def outstanding_orders
      @filter_type ||= begin
        t = params[:order_type].presence
        t == "all" ? nil : t
      end
      @q ||= Order.ransack(params[:q])
      scope = @q.result.not_fully_paid.includes(:customer, :user, :payments)
      scope = scope.where(order_type: @filter_type) if @filter_type.present?
      scope.limit(100).to_a.select { |order| order.amount_due_cents.positive? }
    end

    # The same set that blocks the shift from closing, so pressing the button
    # always clears the blocker rather than leaving a remainder the cashier cannot
    # see. Drafts are in it: a cart with food in it is an unfinished sale.
    def open_orders_for(user)
      Order.not_finalized.where(user: user).includes(:order_items)
    end

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end
  end
end
