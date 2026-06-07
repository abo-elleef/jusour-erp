# frozen_string_literal: true

module Receipts
  class SendReceiptJob < ApplicationJob
    queue_as :mailers

    def perform(order_id, method, recipient)
      order = Order.unscoped.find(order_id)
      with_company(order.company) do
        Receipts::SendReceiptService.call(order: order, method: method, recipient: recipient)
      end
    end
  end
end
