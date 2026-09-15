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

      @q = Order.ransack(params[:q])
      scope = @q.result.not_fully_paid.includes(:customer, :user)
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
      authorize @order, :show?

      @from_shift = params[:from] == "shift"
      @order_items = @order.order_items
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
      raise Pundit::NotAuthorizedError unless order.draft? && order.user == current_user

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

    def print_receipt
      @order = Order.find(params[:id])
      authorize @order, :show?
      Printing::PrintReceiptService.call(order: @order)
      redirect_to pos_order_path(@order, from: params[:from]), notice: t("flash.pos.print_queued")
    end

    def print_all
      @order = Order.find(params[:id])
      authorize @order, :show?
      Printing::PrintReceiptService.call(order: @order)
      Printing::DispatchProductionPrintsService.call(order: @order)
      redirect_to pos_order_path(@order, from: params[:from]), notice: t("flash.pos.print_all_queued")
    end

    private

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end
  end
end
