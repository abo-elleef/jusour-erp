# frozen_string_literal: true

module Printing
  module Escpos
    class ReceiptBuilder
      def initialize(order, printer:)
        @order = order
        @printer = printer
      end

      def build
        doc = Document.new(width: line_width)
        restaurant = Setting.get("restaurant_name", I18n.t("app.name"))

        doc.align(:center)
        doc.bold
        doc.text(restaurant)
        doc.bold(false)
        doc.text(@order.order_number)
        doc.text(@order.created_at.strftime("%b %d, %Y %l:%M %p"))
        doc.text(@order.fulfillment_summary)
        doc.blank
        doc.align(:left)
        doc.rule

        @order.order_items.includes(:order_item_modifiers, :menu_item, :combo).each do |item|
          doc.row("#{item.quantity}x #{item.display_name}", format_money(item.line_total_cents))
          item.order_item_modifiers.each do |modifier|
            doc.text("  + #{modifier.name}")
          end
          doc.text("  #{item.notes}") if item.notes.present?
        end

        doc.rule
        doc.row("Subtotal", format_money(@order.subtotal_cents))
        doc.row("Discount", "-#{format_money(@order.discount_cents)}") if @order.discount_cents.positive?
        doc.row("Tax", format_money(@order.tax_cents))
        doc.row("Tip", format_money(@order.tip_cents)) if @order.tip_cents.positive?

        doc.bold
        doc.row("TOTAL", format_money(@order.total_cents))
        doc.bold(false)
        doc.rule

        print_payments(doc)
        print_change(doc)

        if @order.customer
          doc.blank
          doc.align(:center)
          doc.text("Loyalty: #{@order.customer.loyalty_points} pts")
        end

        doc.blank
        doc.align(:center)
        doc.text(I18n.t("printing.receipt.thank_you"))
        doc.blank(2)
        doc.cut
        doc.to_bytes
      end

      private

      def line_width
        @printer.paper_width == "58mm" ? 32 : 42
      end

      def format_money(cents)
        Money.new(cents.to_i).format(symbol: 'ج.م.')
      end

      def print_payments(doc)
        payments = @order.payments.where(status: "completed").order(:created_at)
        return if payments.none?

        doc.text("Payments:")
        payments.each do |payment|
          label = I18n.t("payment.methods.#{payment.payment_method}", default: payment.payment_method.humanize)
          doc.row("  #{label}", format_money(payment.amount_cents))
        end
      end

      def print_change(doc)
        cash_payments = @order.payments.where(payment_method: "cash", status: "completed")
        return unless cash_payments.one?

        change = cash_payments.first.amount_cents - @order.total_cents
        return unless change.positive?

        doc.row("Change", format_money(change))
      end
    end
  end
end
