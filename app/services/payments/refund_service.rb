# frozen_string_literal: true

module Payments
  class RefundService
    def self.call(order:, amount_cents:, reason:, user:)
      new(order: order, amount_cents: amount_cents, reason: reason, user: user).call
    end

    def initialize(order:, amount_cents:, reason:, user:)
      @order = order
      @amount_cents = amount_cents
      @reason = reason
      @user = user
    end

    def call
      remaining = @amount_cents
      @order.payments.where(status: %w[completed partially_refunded]).find_each do |payment|
        break if remaining <= 0

        refund_amount = [remaining, payment.amount_cents - payment.refunded_amount_cents].min
        next if refund_amount <= 0

        if payment.stripe_charge_id.present?
          Stripe::Refund.create(charge: payment.stripe_charge_id, amount: refund_amount)
        end

        new_refunded = payment.refunded_amount_cents + refund_amount
        status = new_refunded >= payment.amount_cents ? "refunded" : "partially_refunded"
        payment.update!(refunded_amount_cents: new_refunded, refund_reason: @reason, status: status)
        AuditLogEntry.record!(
          action: "payment.refund",
          record: payment,
          user: @user,
          changes_snapshot: { refunded_amount_cents: new_refunded, status: status }
        )
        remaining -= refund_amount
      end

      @order.order_events.create!(
        event_type: "refund",
        user: @user,
        description: "Refunded #{@amount_cents} cents: #{@reason}"
      )
    end
  end
end
