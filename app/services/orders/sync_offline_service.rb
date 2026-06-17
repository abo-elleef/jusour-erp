# frozen_string_literal: true

module Orders
  class SyncOfflineService
    Result = Struct.new(:success?, :order, :errors, keyword_init: true)

    def self.call(user:, payload:)
      new(user: user, payload: payload).call
    end

    def initialize(user:, payload:)
      @user = user
      @payload = payload
    end

    def call
      order = find_order
      return failure("Order not found") unless order
      return failure("Order is not payable") unless order.draft? || order.amount_due_cents.positive?

      apply_tip!(order)
      record_cash_payment!(order)
      Orders::FinalizePaidService.call(order)

      Result.new(success?: true, order: order.reload, errors: [])
    rescue StandardError => e
      failure(e.message)
    end

    private

    def find_order
      id = @payload[:order_id].presence || @payload["order_id"].presence
      return nil if id.blank?

      Order.find_by(id: id, user: @user)
    end

    def apply_tip!(order)
      tip = @payload[:tip_cents].to_i
      order.update!(tip_cents: tip) if tip.positive?
    end

    def record_cash_payment!(order)
      payments = @payload[:payments_attributes] || @payload["payments_attributes"] || []
      payment = payments.first || {}
      amount = payment[:amount_cents].to_i
      amount = order.amount_due_cents if amount <= 0

      Payments::CashPaymentService.call(
        order: order,
        amount_cents: amount,
        tip_cents: 0,
        user: @user
      )
    end

    def failure(message)
      Result.new(success?: false, order: nil, errors: [message])
    end
  end
end
