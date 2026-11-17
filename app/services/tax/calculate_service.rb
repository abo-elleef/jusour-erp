# frozen_string_literal: true

module Tax
  class CalculateService
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      tax_total = 0

      # The active rates are read once for the order, not once per line; each line
      # still gets every active rate of its category, rounded per rate as before.
      rates_by_category = TaxRate.active.to_a.group_by(&:tax_category)

      @order.order_items.includes(:menu_item, :order_item_modifiers).each do |item|
        rates = rates_by_category.fetch(item.tax_category, [])
        line = item.line_total_cents
        rates.each do |rate|
          tax_total += (line * rate.rate).round
        end
      end

      @order.update!(tax_cents: tax_total)
      tax_total
    end
  end
end
