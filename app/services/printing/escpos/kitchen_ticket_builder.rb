# frozen_string_literal: true

module Printing
  module Escpos
    class KitchenTicketBuilder
      def initialize(order, printer:)
        @order = order
        @printer = printer
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
        doc.text(I18n.t("printing.kitchen_ticket.title"))
        doc.double_height(false)
        doc.bold(false)
        doc.text(@order.order_number)
        doc.text(@order.created_at.strftime("%b %d %l:%M %p"))
        doc.bold
        doc.double_height(true)
        doc.text(@order.fulfillment_summary)
        doc.double_height(false)
        doc.bold(false)
        doc.blank

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

        doc.blank(4)
        doc.cut
        doc
      end

      def compose_items_table(doc, items)
        doc.align(:left)
        doc.separator
        doc.row3(I18n.t("printing.receipt.item"), I18n.t("printing.receipt.qty"), I18n.t("printing.receipt.price"))
        doc.separator

        items.each do |item|
          doc.row3(item.display_name, item.quantity.to_s, format_money(item.line_total_cents))
          item.order_item_modifiers.each do |modifier|
            doc.modifier_text("+ #{modifier.name}")
          end
          doc.modifier_text(item.notes) if item.notes.present?
          doc.separator
        end
      end

      def format_money(cents)
        Money.new(cents.to_i).format(symbol: false)
      end

      def line_width
        @printer.paper_width == "58mm" ? 32 : 42
      end
    end
  end
end
