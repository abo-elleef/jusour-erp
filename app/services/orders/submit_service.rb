# frozen_string_literal: true

module Orders
  class SubmitService
    class InvalidFulfillment < StandardError; end

    # dispatch_production: false submits the order without printing kitchen / bar
    # tickets, for a cashier who chose not to (or who already sent them).
    def self.call(order, dispatch_production: true)
      new(order, dispatch_production: dispatch_production).call
    end

    # Raises InvalidFulfillment when the order could not be submitted as it stands.
    # Callers that take money first (payments) must run this before recording any:
    # a payment saved on an order that then fails to submit leaves a paid draft that
    # the kitchen never hears about.
    def self.validate_fulfillment!(order)
      if order.table? && order.table_number.blank?
        raise InvalidFulfillment, I18n.t("order.submit.errors.table_number_required")
      end
      if order.delivery? && order.delivery_address.blank?
        raise InvalidFulfillment, I18n.t("order.submit.errors.delivery_address_required")
      end
    end

    def initialize(order, dispatch_production: true)
      @order = order
      @dispatch_production = dispatch_production
    end

    def call
      self.class.validate_fulfillment!(@order)
      @order.recalculate_totals!
      @order.submit!
      Printing::DispatchProductionPrintsJob.perform_later(@order.id) if @dispatch_production
      @order
    end
  end
end
