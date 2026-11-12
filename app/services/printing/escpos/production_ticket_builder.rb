# frozen_string_literal: true

module Printing
  module Escpos
    class ProductionTicketBuilder
      include IssuedBy
      include TicketItemsTable

      def initialize(order, printer:, order_items:, title:)
        @order = order
        @printer = printer
        @order_items = order_items
        @title = title
      end

      def build
        compose(Document.new(width: line_width, compact: true)).to_bytes
      end

      def build_debug
        doc = DebugDocument.new(width: line_width, compact: true)
        compose(doc)
        doc
      end

      private

      def compose(doc)
        # Same branch/company logo as the customer receipt.
        doc.align(:center)
        doc.receipt_logo(location: @order.location, company: @order.company)

        doc.align(:center)
        doc.bold
        doc.double_height(true)
        doc.text(@title)
        doc.text(@order.display_number)
        # A placed order changed after the PIN: the whole order prints again, and this
        # tells the station it replaces the earlier ticket rather than adds to it.
        if @order.edit_count.to_i.positive?
          doc.text(I18n.t("printing.production_ticket.edited", count: @order.edit_count))
        end
        doc.double_height(false)
        doc.bold(false)
        doc.text(I18n.l(@order.created_at, format: :ticket))
        doc.bold
        doc.double_height(true)
        doc.text(@order.fulfillment_summary)
        doc.double_height(false)
        doc.bold(false)
        compose_issued_by(doc, cashier: @order.user&.name.to_s, station: @order.workstation&.name.to_s)

        compose_items_table(doc, @order_items)

        if @order.notes.present?
          doc.blank
          doc.align(:center)
          doc.bold
          doc.text(I18n.t("printing.production_ticket.order_notes"))
          doc.bold(false)
          doc.text(@order.notes)
          doc.rule
        end

        # The cut command feeds the last line to the cutter itself; no blank lines.
        doc.cut
        doc
      end

      def line_width
        @printer.paper_width == "58mm" ? 32 : 42
      end
    end
  end
end
