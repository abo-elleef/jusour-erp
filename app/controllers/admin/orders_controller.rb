# frozen_string_literal: true

module Admin
  class OrdersController < BaseController
    before_action { require_feature!(:menu) }

    before_action :set_order, only: %i[show void refund change_payment_method]

    def index
      authorize Order

      @focus = params[:focus].presence
      @filter_date = params[:date].presence
      @q = Order.ransack(params[:q])
      scope = @q.result.includes(:user, :customer, :payments, :order_items).order(created_at: :desc)
      scope = scope.on_date(@filter_date) if @filter_date.present?
      scope = apply_focus_filter(scope)

      @pagy, @orders = pagy(:offset, scope, limit: 30)
      @filtered = @focus.present? || @filter_date.present? || params[:q].present?
      @cashiers = User.where(role: %w[cashier manager owner]).order(:name)
      @customers = Customer.order(Arel.sql("COALESCE(name, phone, email)")).limit(500)
      load_order_stats
    end

    def show
      authorize @order
      @order_items = @order.order_items.includes(:menu_item, :combo, :order_item_modifiers)
      @payments = @order.payments.includes(:processed_by_user).order(created_at: :desc)
      @order_events = @order.order_events.includes(:user).order(created_at: :desc)
    end

    def change_payment_method
      authorize @order, :change_payment_method?

      payment = @order.payments.find(params[:payment_id])
      new_method = params[:payment_method].to_s

      unless Payment::METHODS.include?(new_method)
        return redirect_to admin_order_path(@order), alert: t("flash.pos.invalid_payment_method")
      end

      old_method = payment.payment_method
      payment.update!(payment_method: new_method)

      AuditLogEntry.record!(
        action: "payment.change_method",
        record: payment,
        user: current_user,
        changes_snapshot: { from: old_method, to: new_method }
      )

      redirect_to admin_order_path(@order), notice: t("flash.pos.payment_method_changed")
    end

    def void
      authorize @order, :void?
      reason = params[:reason].presence || "Voided by manager"
      @order.payments.where(status: "pending").find_each do |payment|
        if payment.stripe_payment_intent_id
          Payments::StripeTerminalService.cancel_payment_intent(payment.stripe_payment_intent_id)
        end
      end
      @order.cancel! if @order.may_cancel?
      @order.order_events.create!(event_type: "void", user: current_user, description: reason)
      redirect_to admin_order_path(@order), notice: t("flash.order.voided")
    end

    def refund
      authorize @order, :refund?
      Payments::RefundService.call(
        order: @order,
        amount_cents: (params[:amount_pounds].to_f * 100).round,
        reason: params[:reason],
        user: current_user
      )
      redirect_to admin_order_path(@order), notice: t("flash.order.refunded")
    end

    private

    def set_order
      @order = Order.find(params[:id])
    end

    def apply_focus_filter(scope)
      case @focus
      when "open" then scope.open_orders
      when "unpaid" then scope.unpaid
      else scope
      end
    end

    def load_order_stats
      today = BusinessDay.today
      @today_count = Order.on_date(today).count
      # Net of refunds: a refunded order stays "completed" at its full total.
      completed_today = Order.on_date(today).where(status: "completed")
      @today_revenue_cents = completed_today.sum(:total_cents) -
                             ::Accounting::RevenueCalculator.refunds_cents(completed_today.pluck(:id))
      @open_count = Order.open_orders.count
      @unpaid_count = Order.unpaid.count
    end
  end
end
