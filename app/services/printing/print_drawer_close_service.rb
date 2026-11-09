# frozen_string_literal: true

module Printing
  # Queues the closing slip for a cash drawer on the same pipeline as order
  # receipts: through the local print agent of a register by default, or straight
  # from the server when the company routes that way.
  #
  # Printing never blocks closing a drawer. A missing printer or a failure is logged
  # on a PrintLog and the caller carries on.
  class PrintDrawerCloseService
    DUPLICATE_WINDOW = 5.seconds

    def self.call(session:, workstation: nil)
      new(session: session, workstation: workstation).call
    end

    # The slip is a reprint when an earlier one was already queued for this drawer.
    def self.reprint?(print_log)
      return false unless print_log.cash_drawer_session_id

      PrintLog.where(cash_drawer_session_id: print_log.cash_drawer_session_id, print_type: "drawer_close")
              .where("created_at < ?", print_log.created_at).exists?
    end

    def initialize(session:, workstation: nil)
      @session = session
      @workstation = workstation
    end

    def call
      printer = resolve_printer
      return log_skipped(nil, "no_active_receipt_printer") unless printer
      return if repeated_request?(printer)

      if Config.client_routing?
        queue_client_print(printer)
      elsif printer.usb?
        print_via_agent_usb(printer)
      else
        print_via_server(printer)
      end
    rescue Drivers::Network::Error, Drivers::PrintAgent::Error, StandardError => e
      log_failure(printer, e.message)
      Rails.logger.error("[Printing] drawer close failed for session #{@session.id}: #{e.message}")
      nil
    end

    private

    def resolve_printer
      printer = @workstation&.receipt_printer
      return printer if printer&.active?

      Printer.default_for("receipt", location: @session.location)
    end

    # A double tap on Reprint, not two wishes.
    def repeated_request?(printer)
      PrintLog.where(cash_drawer_session_id: @session.id, printer_id: printer.id, print_type: "drawer_close",
                     status: %w[pending sent])
              .where("created_at > ?", DUPLICATE_WINDOW.ago).exists?
    end

    def reprint?
      PrintLog.where(cash_drawer_session_id: @session.id, print_type: "drawer_close").exists?
    end

    def payload(printer)
      Escpos::DrawerCloseBuilder.new(@session, printer: printer, reprint: reprint?).build
    end

    def queue_client_print(printer)
      log = log_pending(printer)
      Turbo::StreamsChannel.broadcast_append_to(
        stream_name,
        target: "client-print-queue",
        partial: "pos/client_prints/job",
        locals: { print_log: log }
      )
      log
    end

    # The register that is closing gets it; with no register known (a manager
    # closing from the admin), it goes to the branch for whichever register is open.
    def stream_name
      if @workstation && @session.location_id.present?
        "pos_prints_#{@session.company_id}_#{@session.location_id}_#{@workstation.id}"
      elsif @session.location_id.present?
        "pos_prints_#{@session.company_id}_#{@session.location_id}"
      else
        "pos_prints_#{@session.company_id}"
      end
    end

    def print_via_agent_usb(printer)
      device = printer.host.to_s.strip
      return log_skipped(printer, "usb_printer_missing_device_name") if device.blank?

      Drivers::PrintAgent.print_usb!(device: device, data: payload(printer))
      log_success(printer)
    end

    def print_via_server(printer)
      Drivers::Network.print!(host: printer.host, port: printer.port || Drivers::Network::DEFAULT_PORT,
                              data: payload(printer))
      log_success(printer)
    end

    def create_log(printer, status, error_message = nil)
      PrintLog.create!(cash_drawer_session: @session, workstation: @workstation, printer: printer,
                       print_type: "drawer_close", status: status, error_message: error_message)
    end

    def log_pending(printer) = create_log(printer, "pending")
    def log_success(printer) = create_log(printer, "sent")
    def log_failure(printer, message) = create_log(printer, "failed", message)
    def log_skipped(printer, reason) = create_log(printer, "skipped", reason)
  end
end
