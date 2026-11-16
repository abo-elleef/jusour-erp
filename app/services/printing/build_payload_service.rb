# frozen_string_literal: true

module Printing
  class BuildPayloadService
    def self.call(printer:, order: nil, drawer_session: nil, reprint: false, print_type: "receipt", host: nil, port: nil, workstation: nil)
      new(order: order, drawer_session: drawer_session, reprint: reprint, printer: printer,
          print_type: print_type, host: host, port: port, workstation: workstation).call
    end

    def initialize(printer:, order: nil, drawer_session: nil, reprint: false, print_type: "receipt", host: nil, port: nil,
                   workstation: nil)
      @drawer_session = drawer_session
      @workstation = workstation
      @reprint = reprint
      @order = order
      @printer = printer
      @print_type = print_type
      @host = host
      @port = port
    end

    def call
      # Compose once to draw every missing image in a single ImageMagick run, then
      # build for real from the cache (see ArabicImageRenderer.prefetch).
      Escpos::ArabicImageRenderer.prefetch { build_bytes }
      payload = build_bytes

      {
        host: @host.presence || @printer.host,
        port: (@port.presence || @printer.port || Drivers::Network::DEFAULT_PORT).to_i,
        printer_name: @printer.name,
        print_type: @print_type,
        connection: @printer.connection_type,
        device: @printer.usb? ? @printer.host : nil,
        data_base64: Base64.strict_encode64(payload)
      }
    end

    private

    def build_bytes
      case @print_type
      when "drawer_close"
        Escpos::DrawerCloseBuilder.new(@drawer_session, printer: @printer, reprint: @reprint,
                                                     workstation: @workstation).build
      when "kitchen"
        Escpos::KitchenTicketBuilder.new(@order, printer: @printer).build
      when "pick_station", "station"
        Escpos::ProductionTicketBuilder.new(
          @order,
          printer: @printer,
          order_items: production_items,
          title: @print_type == "pick_station" ? I18n.t("printing.production_ticket.pick_title") : (@printer.station.presence || @printer.name)
        ).build
      else
        Escpos::ReceiptBuilder.new(@order, printer: @printer).build
      end
    end

    # The pick ticket lists the whole order; a station ticket only the items
    # assigned to that printer (same rule DispatchProductionPrintsService used
    # to decide the station gets a ticket at all).
    def production_items
      items = @order.order_items.includes(:order_item_modifiers, :combo, :order_discounts, menu_item: :category).to_a
      return items if @print_type == "pick_station"

      OrderItemRouting.matching_items(items, @printer)
    end
  end
end
