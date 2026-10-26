# frozen_string_literal: true

module Printing
  module Escpos
    class ProductionTicketBuilder
      def initialize(order, printer:, order_items:, title:)
        @order = order
        @printer = printer
        @order_items = order_items
        @title = title
      end

      def build
        compose(Document.new(width: line_width)).to_bytes
      end

      def build_debug
        doc = DebugDocument.new(width: line_width)
        compose(doc)
        doc
      end

      private

      def compose(doc)
        doc.align(:center)
        doc.bold
        doc.double_height(true)
        doc.text(@title)
        doc.text(@order.order_number)
        doc.double_height(false)
        doc.bold(false)
        doc.text(I18n.l(@order.created_at, format: :ticket))
        doc.bold
        doc.double_height(true)
        doc.text(@order.fulfillment_summary)
        doc.double_height(false)
        doc.bold(false)
        doc.blank

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

        doc.blank(4)
        doc.cut
        doc
      end

      def compose_items_table(doc, items)
        doc.align(:left)
        doc.separator
        doc.row(I18n.t("printing.receipt.item"), I18n.t("printing.receipt.qty"))
        doc.separator

        items.each do |item|
          doc.row(item.display_name, item.quantity.to_s)
          item.order_item_modifiers.each do |modifier|
            doc.modifier_text("+ #{modifier.name}", columns: 2)
          end
          doc.modifier_text(item.notes, columns: 2) if item.notes.present?
          doc.separator
        end
      end

      def line_width
        @printer.paper_width == "58mm" ? 32 : 42
      end
    end
  end
end
