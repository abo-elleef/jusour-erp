# frozen_string_literal: true

module Printing
  class DispatchProductionPrintsService
    def self.call(order:)
      new(order: order).call
    end

    def initialize(order:)
      @order = order
      @items = load_items
    end

    def call
      print_pick_station
      print_station_tickets
      # Recorded so a later payment can offer not to print the same tickets again.
      # update_column on purpose: no validations, no callbacks, nothing about the
      # order's status or payments changes.
      @order.update_column(:kitchen_sent_at, Time.current)
    end

    private

    def load_items
      @order.order_items.includes(:order_item_modifiers, :menu_item, :combo).to_a
    end

    def print_pick_station
      return if @order.location.blank?

      printer = Printer.default_for("expo", location: @order.location)
      return unless printer

      PrintOrderService.call(
        order: @order,
        print_type: "pick_station",
        printer: printer,
        order_items: @items
      )
    end

    def print_station_tickets
      return if @order.location.blank?

      Printer.production_stations.for_location(@order.location).includes(:menu_items).find_each do |printer|
        matching = OrderItemRouting.matching_items(@items, printer)
        next if matching.empty?

        PrintOrderService.call(
          order: @order,
          print_type: "station",
          printer: printer,
          order_items: matching
        )
      end
    end
  end
end
