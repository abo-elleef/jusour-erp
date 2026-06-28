# frozen_string_literal: true

module Admin
  class OrdersController < BaseController
    before_action :set_order, only: %i[show void refund]

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
      today = Date.current
      @today_count = Order.on_date(today).count
      @today_revenue_cents = Order.on_date(today).where(status: "completed").sum(:total_cents)
      @open_count = Order.open_orders.count
      @unpaid_count = Order.unpaid.count
    end
  end
end
