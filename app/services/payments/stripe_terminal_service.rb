# frozen_string_literal: true

module Payments
  class StripeTerminalService
    def self.create_payment_intent(order)
      intent = Stripe::PaymentIntent.create(
        amount: order.total_cents,
        currency: "usd",
        metadata: { order_id: order.id, order_number: order.order_number },
        capture_method: "manual"
      )
      {
        client_secret: intent.client_secret,
        payment_intent_id: intent.id
      }
    end

    def self.capture_payment_intent(payment_intent_id)
      Stripe::PaymentIntent.capture(payment_intent_id)
    end

    def self.cancel_payment_intent(payment_intent_id)
      Stripe::PaymentIntent.cancel(payment_intent_id)
    end
  end
end
