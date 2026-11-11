# frozen_string_literal: true

module Admin
  class OrdersController < BaseController
    before_action { require_feature!(:menu) }

    before_action :set_order, only: %i[show void refund change_payment_method]

    # Sortable columns -> the SQL they order by. Whitelisted: the sort key comes from
    # the URL, so it must never reach the query as text. Cashier, customer and item
    # count are subqueries so no join is added next to the eager loads.
    INDEX_SORTS = {
      "order_number" => "(CASE WHEN orders.order_number ~ '^[0-9]+$' THEN orders.order_number::integer END)",
      "created_at"   => "orders.created_at",
      "cashier"      => "(SELECT users.name FROM users WHERE users.id = orders.user_id)",
      "customer"     => "(SELECT COALESCE(customers.name, customers.phone, customers.email) FROM customers WHERE customers.id = orders.customer_id)",
      "order_type"   => "orders.order_type",
      "status"       => "orders.status",
      "items"        => "(SELECT COUNT(*) FROM order_items WHERE order_items.order_id = orders.id)",
      "total"        => "orders.total_cents"
    }.freeze
    INDEX_DEFAULT_SORT = "created_at"
    INDEX_DEFAULT_DIRECTION = "desc"

    def index
      authorize Order

      @focus = params[:focus].presence
      @filter_date = params[:date].presence
      @q = Order.ransack(params[:q])
      scope = @q.result.includes(:user, :customer, :payments, :order_items)
      scope = scope.on_date(@filter_date) if @filter_date.present?
      scope = apply_focus_filter(scope)
      @sort = INDEX_SORTS.key?(params[:sort].to_s) ? params[:sort].to_s : INDEX_DEFAULT_SORT
      @direction = %w[asc desc].include?(params[:dir].to_s) ? params[:dir].to_s : INDEX_DEFAULT_DIRECTION
      scope = apply_sort(scope)

      @pagy, @orders = pagy(:offset, scope, limit: 50)
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
      result = ::Payments::ChangeMethodService.call(payment: payment, new_method: params[:payment_method], user: current_user)

      if result.success?
        redirect_to admin_order_path(@order), notice: t("flash.pos.payment_method_changed")
      else
        redirect_to admin_order_path(@order), alert: helpers.payment_method_change_error(result.error)
      end
    end

    def void
      authorize @order, :void?
      reason = params[:reason].presence || "Voided by manager"
      unless @order.may_cancel?
        return redirect_to admin_order_path(@order), alert: t("flash.order.cannot_void")
      end

      @order.payments.where(status: "pending").find_each do |payment|
        if payment.stripe_payment_intent_id
          Payments::StripeTerminalService.cancel_payment_intent(payment.stripe_payment_intent_id)
        end
      end
      refunded_cents = 0
      @order.with_lock do
        @order.cancel!
        # A paid order that is voided gives its money back. Leaving the payments as
        # they were kept them in the drawer's expected cash after the cashier had
        # handed the cash back, so the till read short by the whole order.
        refunded_cents = ::Payments::RefundService.call(order: @order, amount_cents: @order.refundable_cents,
                                                        reason: reason, user: current_user)
        @order.order_events.create!(event_type: "void", user: current_user, description: reason)
      end
      notice = if refunded_cents.positive?
                 t("flash.order.voided_and_refunded", amount: helpers.format_money(refunded_cents))
               else
                 t("flash.order.voided")
               end
      redirect_to admin_order_path(@order), notice: notice
    end

    def refund
      authorize @order, :refund?
      amount_cents = (params[:amount_pounds].to_s.tr("٠١٢٣٤٥٦٧٨٩٫", "0123456789.").to_f * 100).round
      if amount_cents <= 0 || amount_cents > @order.refundable_cents
        return redirect_to admin_order_path(@order),
                           alert: t("flash.order.refund_out_of_range", max: helpers.format_money(@order.refundable_cents))
      end

      ::Payments::RefundService.call(order: @order, amount_cents: amount_cents, reason: params[:reason], user: current_user)
      redirect_to admin_order_path(@order), notice: t("flash.order.refunded")
    end

    private

    def set_order
      @order = Order.find(params[:id])
    end

    # Empty values go last either way, and ties fall back to newest first so the page
    # order is stable between clicks.
    def apply_sort(scope)
      scope.reorder(
        Arel.sql("#{INDEX_SORTS.fetch(@sort)} #{@direction.upcase} NULLS LAST"),
        Arel.sql("orders.created_at DESC"),
        Arel.sql("orders.id DESC")
      )
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
