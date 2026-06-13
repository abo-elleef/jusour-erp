# frozen_string_literal: true

module Printing
  module Escpos
    class KitchenTicketBuilder
      def initialize(order, printer:)
        @order = order
        @printer = printer
      end

      def build
        doc = Document.new(width: line_width)
        doc.align(:center)
        doc.bold
        doc.double_height(true)
        doc.text(I18n.t("printing.kitchen_ticket.title"))
        doc.double_height(false)
        doc.bold(false)
        doc.text(@order.order_number)
        doc.text(@order.created_at.strftime("%b %d %l:%M %p"))
        doc.text(@order.fulfillment_summary)
        doc.blank
        doc.align(:left)
        doc.rule

        @order.order_items.includes(:order_item_modifiers, :menu_item, :combo).each do |item|
          doc.bold
          doc.text("#{item.quantity}x #{item.display_name}")
          doc.bold(false)
          item.order_item_modifiers.each do |modifier|
            doc.text("  + #{modifier.name}")
          end
          doc.text("  * #{item.notes}") if item.notes.present?
          doc.blank
        end

        if @order.notes.present?
          doc.rule
          doc.bold
          doc.text(I18n.t("printing.kitchen_ticket.order_notes"))
          doc.bold(false)
          doc.text(@order.notes)
        end

        doc.blank(2)
        doc.cut
        doc.to_bytes
      end

      private

      def line_width
        @printer.paper_width == "58mm" ? 32 : 42
      end
    end
  end
end
