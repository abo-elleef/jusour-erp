# frozen_string_literal: true

module Orders
  # Voids an order: cancels it (which puts stock, loyalty and a posted sales day
  # back for a completed one), refunds whatever was paid, and records who did it.
  # Shared by the admin order page and the register's void-orders PIN.
  class VoidService
    Result = Struct.new(:voided, :refunded_cents, keyword_init: true) do
      def voided? = voided
    end

    def self.call(...) = new(...).call

    def initialize(order:, user:, reason: nil)
      @order = order
      @user = user
      @reason = reason.presence || "Voided by manager"
    end

    def call
      return Result.new(voided: false, refunded_cents: 0) unless @order.may_cancel?

      @order.payments.where(status: "pending").find_each do |payment|
        if payment.stripe_payment_intent_id
          ::Payments::StripeTerminalService.cancel_payment_intent(payment.stripe_payment_intent_id)
        end
      end

      refunded_cents = 0
      @order.with_lock do
        @order.cancel!(by: @user)
        # A paid order that is voided gives its money back. Leaving the payments as
        # they were kept them in the drawer's expected cash after the cashier had
        # handed the cash back, so the till read short by the whole order.
        refunded_cents = ::Payments::RefundService.call(order: @order, amount_cents: @order.refundable_cents,
                                                      reason: @reason, user: @user)
        @order.order_events.create!(event_type: "void", user: @user, description: @reason)
      end
      Result.new(voided: true, refunded_cents: refunded_cents)
    end
  end
end
