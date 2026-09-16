# frozen_string_literal: true

module Printing
  class PrintReceiptJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.unscoped.find_by(id: order_id)
      # Queued when the order is paid off, which can happen before it is completed
      # or long after. Anything but a cart or a void is receiptable.
      return if order.nil? || order.draft? || order.cancelled?

      with_company(order.company) do
        PrintReceiptService.call(order: order)
      end
    end
  end
end
