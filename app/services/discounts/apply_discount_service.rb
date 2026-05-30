# frozen_string_literal: true

module Discounts
  class ApplyDiscountService
    class InvalidDiscount < StandardError; end

    def self.call(order:, code: nil, rule: nil, manager_override_cents: nil, description: nil)
      new(order: order, code: code, rule: rule,
          manager_override_cents: manager_override_cents, description: description).call
    end

    def initialize(order:, code: nil, rule: nil, manager_override_cents: nil, description: nil)
      @order = order
      @code = code
      @rule = rule
      @manager_override_cents = manager_override_cents
      @description = description
    end

    def call
      if @manager_override_cents
        apply_override!
      else
        apply_coupon!
      end
      @order.recalculate_totals!
      @order
    end

    private

    def apply_override!
      @order.order_discounts.create!(
        description: @description || "Manager Override",
        amount_cents: @manager_override_cents
      )
    end

    def apply_coupon!
      rule = @rule || DiscountRule.valid_now.find_by!(code: @code)
      raise InvalidDiscount, "Coupon not valid" unless rule.usable?

      if @order.subtotal_cents.to_i < rule.minimum_order_cents
        raise InvalidDiscount, "Order does not meet minimum"
      end

      amount = calculate_amount(rule)
      @order.order_discounts.create!(
        discount_rule: rule,
        description: rule.name,
        amount_cents: amount
      )
      rule.decrement!(:uses_remaining) if rule.uses_remaining.present?
    end

    def calculate_amount(rule)
      case rule.applies_to
      when "order"
        discount_on(rule, @order.subtotal_cents.to_i)
      when "item"
        lines = @order.order_items.where(menu_item_id: rule.applies_to_id)
        lines.sum { |l| discount_on(rule, l.line_total_cents) }
      when "category"
        cat_id = rule.applies_to_id
        lines = @order.order_items.joins(:menu_item).where(menu_items: { category_id: cat_id })
        lines.sum { |l| discount_on(rule, l.line_total_cents) }
      else
        0
      end
    end

    def discount_on(rule, base_cents)
      if rule.discount_type == "percentage"
        (base_cents * rule.discount_value / 100).round
      else
        [rule.discount_value.to_i, base_cents].min
      end
    end
  end
end
