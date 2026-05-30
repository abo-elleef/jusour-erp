# frozen_string_literal: true

module Receipts
  class SendReceiptJob < ApplicationJob
    queue_as :mailers

    def perform(order_id, method, recipient)
      order = Order.find(order_id)
      Receipts::SendReceiptService.call(order: order, method: method, recipient: recipient)
    end
  end
end
