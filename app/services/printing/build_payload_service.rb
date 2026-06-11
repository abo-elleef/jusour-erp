# frozen_string_literal: true

module Printing
  class BuildPayloadService
    def self.call(order:, printer:, host: nil, port: nil)
      new(order: order, printer: printer, host: host, port: port).call
    end

    def initialize(order:, printer:, host: nil, port: nil)
      @order = order
      @printer = printer
      @host = host
      @port = port
    end

    def call
      payload = Escpos::ReceiptBuilder.new(@order, printer: @printer).build
      {
        host: @host.presence || @printer.host,
        port: (@port.presence || @printer.port || Drivers::Network::DEFAULT_PORT).to_i,
        printer_name: @printer.name,
        data_base64: Base64.strict_encode64(payload)
      }
    end
  end
end
