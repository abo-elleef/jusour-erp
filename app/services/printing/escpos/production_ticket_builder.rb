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
        doc = Document.new(width: line_width)
        doc.align(:center)
        doc.bold
        doc.double_height(true)
        doc.text(@title)
        doc.double_height(false)
        doc.bold(false)
        doc.text(@order.order_number)
        doc.text(I18n.l(@order.created_at, format: :short))
        doc.text(I18n.l(Time.current, format: :short))
        doc.text(@order.fulfillment_summary)
        doc.blank
        doc.align(:left)
        doc.rule

        @order_items.each do |item|
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
          doc.text(I18n.t("printing.production_ticket.order_notes"))
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
