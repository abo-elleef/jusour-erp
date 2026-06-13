# frozen_string_literal: true

module Printing
  class PrintOrderService
    def self.call(order:, print_type:)
      new(order: order, print_type: print_type).call
    end

    def initialize(order:, print_type:)
      @order = order
      @print_type = print_type
    end

    def call
      printer = Printer.default_for(@print_type)
      return log_skipped(nil, "no_active_#{@print_type}_printer") unless printer

      if printer.usb?
        return log_skipped(printer, "usb_printer_requires_local_agent")
      end

      payload = build_payload(printer)

      if Config.client_routing?
        queue_client_print(printer, payload)
      else
        print_via_server(printer, payload)
      end
    rescue Drivers::Network::Error, StandardError => e
      log_failure(printer, e.message)
      Rails.logger.error("[Printing] #{@print_type} failed for order #{@order.order_number}: #{e.message}")
    end

    private

    def build_payload(printer)
      case @print_type
      when "kitchen"
        Escpos::KitchenTicketBuilder.new(@order, printer: printer).build
      else
        Escpos::ReceiptBuilder.new(@order, printer: printer).build
      end
    end

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
        print_type: @print_type,
        status: "sent"
      )
    end

    def log_pending(printer)
      PrintLog.create!(
        order: @order,
        printer: printer,
        print_type: @print_type,
        status: "pending"
      )
    end

    def log_failure(printer, message)
      PrintLog.create!(
        order: @order,
        printer: printer,
        print_type: @print_type,
        status: "failed",
        error_message: message
      )
    end

    def log_skipped(printer, reason)
      PrintLog.create!(
        order: @order,
        printer: printer,
        print_type: @print_type,
        status: "skipped",
        error_message: reason
      )
    end
  end
end
