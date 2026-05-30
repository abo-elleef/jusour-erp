# frozen_string_literal: true

module Loyalty
  class RedeemPointsService
    class InsufficientPoints < StandardError; end

    def self.call(order:)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      customer = @order.customer or raise InsufficientPoints, "No customer on order"

      threshold = Setting.get_int("loyalty_redeem_threshold", 100)
      value_cents = Setting.get_int("loyalty_redeem_value_cents", 500)

      raise InsufficientPoints, "Not enough points" if customer.loyalty_points < threshold

      customer.loyalty_transactions.create!(
        order: @order,
        transaction_type: "redeemed",
        points: -threshold,
        description: "Redeemed #{threshold} points"
      )
      customer.decrement!(:loyalty_points, threshold)

      @order.order_discounts.create!(
        description: "Loyalty redemption (#{threshold} pts)",
        amount_cents: value_cents
      )
      @order.recalculate_totals!
    end
  end
end
