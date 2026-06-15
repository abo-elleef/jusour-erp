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
      Printing::DispatchProductionPrintsJob.perform_later(@order.id)
      @order
    end

    private

    def validate_fulfillment!
      if @order.table? && @order.table_number.blank?
        raise InvalidFulfillment, I18n.t("order.submit.errors.table_number_required")
      end
      if @order.delivery? && @order.delivery_address.blank?
        raise InvalidFulfillment, I18n.t("order.submit.errors.delivery_address_required")
      end
    end
  end
end
