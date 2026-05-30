# frozen_string_literal: true

module Payments
  class CashPaymentService
    def self.call(order:, amount_cents:, tip_cents:, user:)
      order.payments.create!(
        payment_method: "cash",
        amount_cents: amount_cents,
        tip_cents: tip_cents,
        status: "completed",
        processed_by_user: user
      )
      order.update!(tip_cents: order.tip_cents + tip_cents) if tip_cents.positive?
      complete_order_if_paid(order)
    end

    def self.complete_order_if_paid(order)
      return unless order.fully_paid?

      order.mark_ready! if order.may_mark_ready?
      order.complete! if order.may_complete?
    end
  end
end
