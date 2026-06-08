# frozen_string_literal: true

module Accounting
  class RevenueCalculator
    ORDER_ITEM_LINE_REVENUE = <<~SQL.squish.freeze
      (order_items.quantity * order_items.unit_price_cents) +
      (order_items.quantity * COALESCE(
        (SELECT SUM(order_item_modifiers.price_adjustment_cents)
         FROM order_item_modifiers
         WHERE order_item_modifiers.order_item_id = order_items.id), 0))
    SQL

    ORDER_NET_SALES = "(orders.subtotal_cents - orders.discount_cents)"

    def self.order_item_revenue(scope)
      scope.sum(Arel.sql(ORDER_ITEM_LINE_REVENUE)).to_i
    end

    def self.order_net_sales(scope)
      scope.sum(Arel.sql(ORDER_NET_SALES)).to_i
    end

    def self.refunds_cents(order_ids)
      return 0 if order_ids.blank?

      Payment.where(order_id: order_ids, status: %w[refunded partially_refunded])
             .sum(:refunded_amount_cents).to_i
    end
  end
end
