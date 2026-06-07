# frozen_string_literal: true

module Loyalty
  class AwardPointsJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.unscoped.find(order_id)
      with_company(order.company) do
        Loyalty::AwardPointsService.call(order)
      end
    end
  end
end
