# frozen_string_literal: true

module Printing
  class PrintReceiptService
    def self.call(order:, manual: false)
      PrintOrderService.call(order: order, print_type: "receipt", manual: manual)
    end
  end
end
