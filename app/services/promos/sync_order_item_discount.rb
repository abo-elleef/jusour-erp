# frozen_string_literal: true

module Promos
  class SyncOrderItemDiscount
    def self.call(order_item:)
      new(order_item:).call
    end

    def initialize(order_item:)
      @order_item = order_item
      @order = order_item.order
    end

    def call
      existing = @order.order_discounts.find_by(order_item_id: @order_item.id)

      if @order_item.menu_item_id.blank?
        existing&.destroy!
        return
      end

      promo = Menus::ActivePromo.for(
        menu_item: @order_item.menu_item,
        location: @order.location,
        modifier_ids: @order_item.order_item_modifiers.pluck(:modifier_id)
      )

      if promo.blank? || promo.discount_cents <= 0
        existing&.destroy!
        return
      end

      amount = promo.discount_cents * @order_item.quantity
      attrs = {
        menu_promo_id: promo.promo.id,
        description: I18n.t("promos.order_discount_description", name: promo.label),
        amount_cents: amount
      }

      if existing
        existing.update!(attrs)
      else
        @order.order_discounts.create!(attrs.merge(order_item_id: @order_item.id))
      end
    end
  end
end
