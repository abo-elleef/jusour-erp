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
      # Branches that make the delivery area compulsory (Location#require_delivery_area).
      # Checked on every place and re-place, and again before any money is taken
      # (Pos::PaymentsController#require_delivery_area!).
      if order.needs_delivery_area?
        raise InvalidFulfillment, I18n.t("order.submit.errors.delivery_area_required")
      end
      # Branches that ask for the customer on pickup (Location#pickup_customer_prompt):
      # the register's phone popup normally gets there first; this is the safety
      # net. Register orders only, and only before they are first placed: offline,
      # online and call-center orders bring their own customer details, and an
      # order placed before the branch switched this on is not held up on re-place.
      if order.source == "pos" && order.draft? && order.needs_pickup_customer?
        raise InvalidFulfillment, I18n.t("order.submit.errors.pickup_customer_required")
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
