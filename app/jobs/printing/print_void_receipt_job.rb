# frozen_string_literal: true

module Printing
  # The customer receipt again after a void, with a VOIDED banner, the reason and
  # who voided it (ReceiptBuilder draws those for a cancelled order). Queued by
  # Orders::VoidService. PrintReceiptJob skips cancelled orders on purpose, so this
  # is its own job.
  class PrintVoidReceiptJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.unscoped.find_by(id: order_id)
      return unless order&.cancelled?

      with_company(order.company) do
        # manual: a void is deliberate, never a double tap on an earlier receipt.
        PrintReceiptService.call(order: order, manual: true)
      end
    end
  end
end
