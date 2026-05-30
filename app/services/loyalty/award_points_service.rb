# frozen_string_literal: true

module Loyalty
  class AwardPointsService
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      return unless @order.customer

      rate = Setting.get_int("loyalty_earn_rate", 1)
      dollars = (@order.total_cents - @order.tip_cents) / 100.0
      points = (dollars * rate).floor
      return if points <= 0

      @order.customer.loyalty_transactions.create!(
        order: @order,
        transaction_type: "earned",
        points: points,
        description: "Points earned on #{@order.order_number}"
      )
      @order.customer.increment!(:loyalty_points, points)
      @order.customer.increment!(:total_spent_cents, @order.total_cents - @order.tip_cents)
    end
  end
end
