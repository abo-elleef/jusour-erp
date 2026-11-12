# frozen_string_literal: true

module Printing
  module Escpos
    class KitchenTicketBuilder
      include IssuedBy
      include TicketItemsTable

      def initialize(order, printer:)
        @order = order
        @printer = printer
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
        doc.text(I18n.t("printing.kitchen_ticket.title"))
        doc.text(@order.order_number)
        doc.double_height(false)
        doc.bold(false)
        doc.text(@order.created_at.strftime("%b %d %l:%M %p"))
        doc.bold
        doc.double_height(true)
        doc.text(@order.fulfillment_summary)
        doc.double_height(false)
        doc.bold(false)
        compose_issued_by(doc, cashier: @order.user&.name.to_s, station: @order.workstation&.name.to_s)

        items = @order.order_items.includes(:order_item_modifiers, :menu_item, :combo)
        compose_items_table(doc, items)

        if @order.notes.present?
          doc.blank
          doc.align(:center)
          doc.bold
          doc.text(I18n.t("printing.kitchen_ticket.order_notes"))
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
