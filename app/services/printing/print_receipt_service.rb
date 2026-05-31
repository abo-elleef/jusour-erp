# frozen_string_literal: true

module Printing
  class PrintReceiptService
    def self.call(order:)
      new(order: order).call
    end

    def initialize(order:)
      @order = order
    end

    def call
      printer = Printer.default_for("receipt")
      return log_skipped(nil, "no_active_receipt_printer") unless printer

      if printer.usb?
        return log_skipped(printer, "usb_printer_requires_local_agent")
      end

      payload = Escpos::ReceiptBuilder.new(@order, printer: printer).build
      Drivers::Network.print!(host: printer.host, port: printer.port || Drivers::Network::DEFAULT_PORT, data: payload)
      log_success(printer)
    rescue Drivers::Network::Error, StandardError => e
      log_failure(printer, e.message)
      Rails.logger.error("[Printing] Receipt failed for order #{@order.order_number}: #{e.message}")
    end

    private

    def log_success(printer)
      PrintLog.create!(
        order: @order,
        printer: printer,
        print_type: "receipt",
        status: "sent"
      )
    end

    def log_failure(printer, message)
      PrintLog.create!(
        order: @order,
        printer: printer,
        print_type: "receipt",
        status: "failed",
        error_message: message
      )
    end

    def log_skipped(printer, reason)
      PrintLog.create!(
        order: @order,
        printer: printer,
        print_type: "receipt",
        status: "skipped",
        error_message: reason
      )
    end
  end
end
