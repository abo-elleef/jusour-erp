# frozen_string_literal: true

module Printing
  class PrintReceiptService
    def self.call(order:)
      PrintOrderService.call(order: order, print_type: "receipt")
    end
  end
end
