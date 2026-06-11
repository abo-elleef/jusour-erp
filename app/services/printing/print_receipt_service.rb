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

      if Config.client_routing?
        queue_client_print(printer, payload)
      else
        print_via_server(printer, payload)
      end
    rescue Drivers::Network::Error, StandardError => e
      log_failure(printer, e.message)
      Rails.logger.error("[Printing] Receipt failed for order #{@order.order_number}: #{e.message}")
    end

    private

    def print_via_server(printer, payload)
      Drivers::Network.print!(
        host: printer.host,
        port: printer.port || Drivers::Network::DEFAULT_PORT,
        data: payload
      )
      log_success(printer)
    end

    def queue_client_print(printer, payload)
      log = log_pending(printer)
      Turbo::StreamsChannel.broadcast_append_to(
        pos_print_stream_name,
        target: "client-print-queue",
        partial: "pos/client_prints/job",
        locals: { print_log: log, order: @order }
      )
      log
    end

    def pos_print_stream_name
      "pos_prints_#{@order.company_id}"
    end

    def log_success(printer)
      PrintLog.create!(
        order: @order,
        printer: printer,
        print_type: "receipt",
        status: "sent"
      )
    end

    def log_pending(printer)
      PrintLog.create!(
        order: @order,
        printer: printer,
        print_type: "receipt",
        status: "pending"
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
