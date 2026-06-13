# frozen_string_literal: true

module Printing
  class BuildPayloadService
    def self.call(order:, printer:, print_type: "receipt", host: nil, port: nil)
      new(order: order, printer: printer, print_type: print_type, host: host, port: port).call
    end

    def initialize(order:, printer:, print_type: "receipt", host: nil, port: nil)
      @order = order
      @printer = printer
      @print_type = print_type
      @host = host
      @port = port
    end

    def call
      payload = case @print_type
                when "kitchen"
                  Escpos::KitchenTicketBuilder.new(@order, printer: @printer).build
                else
                  Escpos::ReceiptBuilder.new(@order, printer: @printer).build
                end

      {
        host: @host.presence || @printer.host,
        port: (@port.presence || @printer.port || Drivers::Network::DEFAULT_PORT).to_i,
        printer_name: @printer.name,
        print_type: @print_type,
        data_base64: Base64.strict_encode64(payload)
      }
    end
  end
end
