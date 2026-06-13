# frozen_string_literal: true

module Printing
  class PrintOrderJob < ApplicationJob
    queue_as :default

    def perform(order_id, print_type = "receipt")
      order = Order.unscoped.includes(
        :customer,
        :payments,
        order_items: [:order_item_modifiers, :menu_item, :combo]
      ).find_by(id: order_id)
      return unless order

      return if print_type == "receipt" && !order.completed?
      return if print_type == "kitchen" && order.draft?

      with_company(order.company) do
        I18n.with_locale(I18n.default_locale) do
          PrintOrderService.call(order: order, print_type: print_type)
        end
      end
    end
  end
end
