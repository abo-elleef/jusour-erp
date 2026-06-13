# frozen_string_literal: true

module Printing
  class PrintReceiptJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      PrintOrderJob.perform_now(order_id, "receipt")
    end
  end
end
