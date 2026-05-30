# frozen_string_literal: true

module Admin
  class OrdersController < BaseController
    before_action :set_order, only: %i[show void refund]

    def index
      authorize Order

      @q = Order.ransack(params[:q])
      scope = @q.result.includes(:user, :customer).order(created_at: :desc)

      @filter_date = params[:date].presence
      scope = scope.on_date(@filter_date) if @filter_date.present?

      @pagy, @orders = pagy(:offset, scope, limit: 30)
      @cashiers = User.where(role: %w[cashier manager owner]).order(:name)
      @customers = Customer.order(Arel.sql("COALESCE(name, phone, email)")).limit(500)
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
      redirect_to admin_order_path(@order), notice: "Order voided."
    end

    def refund
      authorize @order, :refund?
      Payments::RefundService.call(
        order: @order,
        amount_cents: params[:amount_cents].to_i,
        reason: params[:reason],
        user: current_user
      )
      redirect_to admin_order_path(@order), notice: "Refund processed."
    end

    private

    def set_order
      @order = Order.find(params[:id])
    end
  end
end
