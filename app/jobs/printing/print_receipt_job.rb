# frozen_string_literal: true

module Printing
  class PrintReceiptJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.includes(
        :customer,
        :payments,
        order_items: [:order_item_modifiers, :menu_item, :combo]
      ).find_by(id: order_id)
      return unless order&.completed?

      PrintReceiptService.call(order: order)
    end
  end
end
