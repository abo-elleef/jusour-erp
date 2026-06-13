# frozen_string_literal: true

module Orders
  class SubmitService
    class InvalidFulfillment < StandardError; end

    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      validate_fulfillment!
      @order.recalculate_totals!
      @order.submit!
      Printing::PrintOrderJob.perform_later(@order.id, "kitchen")
      @order
    end

    private

    def validate_fulfillment!
      if @order.table? && @order.table_number.blank?
        raise InvalidFulfillment, "Table number is required for table orders."
      end
      if @order.delivery? && @order.delivery_address.blank?
        raise InvalidFulfillment, "Delivery address is required for delivery orders."
      end
    end
  end
end
