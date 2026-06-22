# frozen_string_literal: true

module Admin
  class PrintDebugController < BaseController
    before_action :require_debug_mode

    def show
      @order = Order.unscoped.find(params[:order_id])
      @tickets = []

      # ── Receipt ────────────────────────────────────────────────────────────
      receipt_printer = Printer.default_for("receipt", location: @order.location) ||
                        Printer.new(paper_width: "80mm", name: "(default)")
      @tickets << {
        label: "Receipt",
        printer_name: receipt_printer.name,
        printer_type: "receipt",
        debug: Printing::Escpos::ReceiptBuilder.new(@order, printer: receipt_printer).build_debug
      }

      items = @order.order_items.includes(:order_item_modifiers, :menu_item, :combo).to_a

      # ── Expo / Pick station ────────────────────────────────────────────────
      expo_printer = Printer.default_for("expo", location: @order.location)
      if expo_printer
        title = I18n.t("printing.production_ticket.pick_station")
        @tickets << {
          label: "Expo — #{expo_printer.name}",
          printer_name: expo_printer.name,
          printer_type: "expo",
          debug: Printing::Escpos::ProductionTicketBuilder.new(
            @order, printer: expo_printer, order_items: items, title: title
          ).build_debug
        }
      end

      # ── Kitchen / Bar stations ─────────────────────────────────────────────
      Printer.production_stations.for_location(@order.location).includes(:menu_items).each do |printer|
        matching = Printing::OrderItemRouting.matching_items(items, printer)
        next if matching.empty?

        station_label = printer.station.presence || printer.name
        @tickets << {
          label: "#{printer.printer_type.capitalize} — #{station_label}",
          printer_name: printer.name,
          printer_type: printer.printer_type,
          debug: Printing::Escpos::ProductionTicketBuilder.new(
            @order, printer: printer, order_items: matching,
            title: station_label
          ).build_debug
        }
      end

      # Legacy: always keep @debug pointing to the receipt for backward compat
      @debug = @tickets.first[:debug]
    end

    private

    def require_debug_mode
      return if ENV["PRINT_DEBUG"] == "true"

      redirect_to admin_root_path, alert: "Set PRINT_DEBUG=true to enable print preview."
    end
  end
end
