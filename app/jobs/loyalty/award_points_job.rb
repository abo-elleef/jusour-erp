# frozen_string_literal: true

module Loyalty
  class AwardPointsJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.find(order_id)
      Loyalty::AwardPointsService.call(order)
    end
  end
end
