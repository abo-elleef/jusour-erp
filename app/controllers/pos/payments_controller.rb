# frozen_string_literal: true

module Pos
  class PaymentsController < ApplicationController
    before_action :require_pos_access!
    before_action :set_order
    before_action :authorize_payment!

    def create
      tip_cents = if params[:tip_pounds].present?
        (params[:tip_pounds].to_f * 100).round
      else
        params[:tip_cents].to_i
      end
      @order.update!(tip_cents: tip_cents) if tip_cents.positive?

      case params[:payment_method]
      when "cash", "instapay", "vodafone_cash"
        Payments::CashPaymentService.call(
          order: @order,
          amount_cents: (params[:amount_pounds].to_f * 100).round,
          tip_cents: 0,
          user: current_user,
          payment_method: params[:payment_method]
        )
      when "card"
        process_card_payment
      when "gift_card"
        process_gift_card
      when "staff_deduction"
        process_staff_meal
      end

      attach_tip_to_largest_payment(tip_cents)
      finalize_if_paid
      redirect_after_payment(notice: t("flash.pos.payment_recorded"))
    end

    def stripe_intent
      @order.recalculate_totals!
      result = Payments::StripeTerminalService.create_payment_intent(@order)
      render json: result.merge(success: true)
    end

    def capture_stripe
      intent = Payments::StripeTerminalService.capture_payment_intent(params[:payment_intent_id])
      @order.payments.create!(
        payment_method: "card",
        amount_cents: intent.amount,
        tip_cents: params[:tip_cents].to_i, # sent as cents from Stimulus card payment handler
        status: "completed",
        stripe_payment_intent_id: intent.id,
        stripe_charge_id: intent.latest_charge,
        processed_by_user: current_user
      )
      finalize_if_paid
      render json: { success: true, redirect_url: payment_return_path }
    end

    private

    def require_pos_access!
      return if current_user&.can_access_pos?

      flash[:alert] = t("flash.pos_access")
      redirect_to root_path
    end

    def set_order
      order_id = params[:order_id].presence || session[:checkout_order_id].presence || session[:current_order_id]
      @order = Order.find(order_id)
    end

    def authorize_payment!
      if @order.draft?
        authorize @order, :update?
      else
        authorize @order, :record_payment?
      end
    end

    def process_card_payment
      # Handled via stripe_intent + capture_stripe
    end

    def process_staff_meal
      staff_user = User.find(params[:staff_meal_user_id])
      treasury   = Treasury.default_treasury
      raise ActiveRecord::RecordNotFound, "No default treasury configured" unless treasury

      Payments::StaffMealPaymentService.call(
        order: @order,
        staff_meal_user: staff_user,
        treasury: treasury,
        processed_by: current_user
      )
    end

    def process_gift_card
      card = GiftCard.active.find_by!(code: params[:gift_card_code])
      amount = [params[:amount_cents].to_i, card.balance_cents, @order.amount_due_cents].min
      card.redeem!(amount)
      @order.payments.create!(
        payment_method: "gift_card",
        amount_cents: amount,
        status: "completed",
        processed_by_user: current_user
      )
    end

    def attach_tip_to_largest_payment(tip_cents)
      return unless tip_cents.positive?

      payment = @order.payments.order(amount_cents: :desc).first
      payment&.update!(tip_cents: tip_cents)
    end

    def finalize_if_paid
      return unless @order.fully_paid?

      Orders::FinalizePaidService.call(@order)
      clear_cart_sessions
      Receipts::SendReceiptJob.perform_later(@order.id, params[:receipt_method], params[:receipt_recipient]) if params[:receipt_method].present?
    end

    def clear_cart_sessions
      session.delete(:current_order_id) if session[:current_order_id] == @order.id
      session.delete(:checkout_order_id) if session[:checkout_order_id] == @order.id
    end

    def checkout_payment?
      session[:checkout_order_id] == @order.id
    end

    def payment_return_path
      if checkout_payment?
        @order.fully_paid? ? pos_orders_path(order_type: @order.order_type) : pos_order_path(@order)
      else
        pos_path
      end
    end

    def redirect_after_payment(notice:)
      redirect_to payment_return_path, notice: notice
    end
  end
end
