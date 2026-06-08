# frozen_string_literal: true

module Pos
  class OrdersController < ApplicationController
    layout "pos"

    before_action :require_pos_access!

    def index
      authorize Order, :index_for_payment?

      @filter_type = params[:order_type].presence
      @filter_type = nil if @filter_type == "all"

      @q = Order.ransack(params[:q])
      scope = @q.result.awaiting_payment.includes(:customer, :user)
      scope = scope.where(order_type: @filter_type) if @filter_type.present?

      orders = scope.limit(100).to_a
      @orders = orders.select { |order| order.amount_due_cents.positive? }
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

      if @order.amount_due_cents.zero?
        redirect_to pos_orders_path(order_type: @order.order_type), notice: t("flash.pos.already_paid")
        return
      end

      authorize @order, :checkout?
      session[:checkout_order_id] = @order.id
      @order_items = @order.order_items
      @payments = @order.payments.order(created_at: :desc)
    end

    private

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end
  end
end
