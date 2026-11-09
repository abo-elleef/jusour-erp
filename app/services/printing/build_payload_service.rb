# frozen_string_literal: true

module Printing
  class BuildPayloadService
    def self.call(printer:, order: nil, drawer_session: nil, reprint: false, print_type: "receipt", host: nil, port: nil)
      new(order: order, drawer_session: drawer_session, reprint: reprint, printer: printer,
          print_type: print_type, host: host, port: port).call
    end

    def initialize(printer:, order: nil, drawer_session: nil, reprint: false, print_type: "receipt", host: nil, port: nil)
      @drawer_session = drawer_session
      @reprint = reprint
      @order = order
      @printer = printer
      @print_type = print_type
      @host = host
      @port = port
    end

    def call
      payload = case @print_type
                when "drawer_close"
                  Escpos::DrawerCloseBuilder.new(@drawer_session, printer: @printer, reprint: @reprint).build
                when "kitchen"
                  Escpos::KitchenTicketBuilder.new(@order, printer: @printer).build
                when "pick_station", "station"
                  Escpos::ProductionTicketBuilder.new(
                    @order,
                    printer: @printer,
                    order_items: @order.order_items.includes(:order_item_modifiers, :menu_item, :combo),
                    title: @print_type == "pick_station" ? I18n.t("printing.production_ticket.pick_title") : (@printer.station.presence || @printer.name)
                  ).build
                else
                  Escpos::ReceiptBuilder.new(@order, printer: @printer).build
                end

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
  end
end
