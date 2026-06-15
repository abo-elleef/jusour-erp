# frozen_string_literal: true

module Printing
  class DispatchProductionPrintsJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.unscoped.find_by(id: order_id)
      return unless order
      return if order.draft? || order.cancelled?

      with_company(order.company) do
        DispatchProductionPrintsService.call(order: order)
      end
    end
  end
end
