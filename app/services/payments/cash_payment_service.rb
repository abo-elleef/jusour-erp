# frozen_string_literal: true

module Payments
  class CashPaymentService
    def self.call(order:, amount_cents:, tip_cents:, user:, payment_method: "cash")
      order.payments.create!(
        payment_method: payment_method,
        amount_cents: amount_cents,
        tip_cents: tip_cents,
        status: "completed",
        processed_by_user: user,
        cash_drawer_session: user.open_cash_drawer_session
      )
      order.update!(tip_cents: order.tip_cents + tip_cents) if tip_cents.positive?
    end
  end
end
