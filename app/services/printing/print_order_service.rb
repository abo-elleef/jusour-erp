# frozen_string_literal: true

module Printing
  class PrintOrderService
    def self.call(order:, print_type:, printer: nil, order_items: nil)
      new(order: order, print_type: print_type, printer: printer, order_items: order_items).call
    end

    def initialize(order:, print_type:, printer: nil, order_items: nil)
      @order = order
      @print_type = print_type
      @printer = printer
      @order_items = order_items
    end

    def call
      printer = @printer || resolve_printer
      return log_skipped(nil, "no_active_#{@print_type}_printer") unless printer

      payload = build_payload(printer)

      # USB and network both go through the local POS print agent in client mode,
      # so each register talks to the printer attached to that machine.
      if Config.client_routing?
        queue_client_print(printer, payload)
      elsif printer.usb?
        print_via_agent_usb(printer, payload)
      else
        print_via_server(printer, payload)
      end
    rescue Drivers::Network::Error, Drivers::PrintAgent::Error, StandardError => e
      log_failure(printer, e.message)
      Rails.logger.error("[Printing] #{@print_type} failed for order #{@order.order_number}: #{e.message}")
    end

    private

    def resolve_printer
      if @print_type == "receipt"
        workstation_printer = @order.workstation&.receipt_printer
        return workstation_printer if workstation_printer&.active?
      end

      Printer.default_for(default_printer_type, location: @order.location)
    end

    def default_printer_type
      case @print_type
      when "pick_station" then "expo"
      when "station" then @printer&.printer_type || "kitchen"
      else @print_type
      end
    end

    def build_payload(printer)
      case @print_type
      when "receipt"
        Escpos::ReceiptBuilder.new(@order, printer: printer).build
      when "kitchen"
        Escpos::KitchenTicketBuilder.new(@order, printer: printer).build
      when "pick_station", "station"
        Escpos::ProductionTicketBuilder.new(
          @order,
          printer: printer,
          order_items: ticket_items,
          title: production_title(printer)
        ).build
      else
        Escpos::ReceiptBuilder.new(@order, printer: printer).build
      end
    end

    def ticket_items
      return @order_items if @order_items

      @order.order_items.includes(:order_item_modifiers, :menu_item, :combo).to_a
    end

    def production_title(printer)
      if @print_type == "pick_station"
        I18n.t("printing.production_ticket.pick_title")
      else
        printer.station.presence || printer.name
      end
    end

    def print_via_agent_usb(printer, payload)
      device = printer.host.to_s.strip
      if device.blank?
        return log_skipped(printer, "usb_printer_missing_device_name")
      end

      Drivers::PrintAgent.print_usb!(device: device, data: payload)
      log_success(printer)
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

    # Receipts bound to a workstation go to that register only.
    # Kitchen/bar/expo stay on the shared branch stream.
    def pos_print_stream_name
      if receipt_for_workstation?
        "pos_prints_#{@order.company_id}_#{@order.location_id}_#{@order.workstation_id}"
      elsif @order.location_id.present?
        "pos_prints_#{@order.company_id}_#{@order.location_id}"
      else
        "pos_prints_#{@order.company_id}"
      end
    end

    def receipt_for_workstation?
      @print_type == "receipt" && @order.workstation_id.present? && @order.location_id.present?
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
