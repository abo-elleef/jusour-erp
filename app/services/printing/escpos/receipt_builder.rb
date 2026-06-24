# frozen_string_literal: true

module Printing
  module Escpos
    class ReceiptBuilder
      def initialize(order, printer:)
        @order   = order
        @printer = printer
      end

      # Returns raw ESC/POS bytes to send to the printer.
      def build
        compose(Document.new(width: line_width)).to_bytes
      end

      # Returns a DebugDocument with entries captured for browser preview.
      # Only used when PRINT_DEBUG=true.
      def build_debug
        doc = DebugDocument.new(width: line_width)
        compose(doc)
        doc
      end

      private

      def compose(doc)
        restaurant = Setting.get("restaurant_name", I18n.t("app.name"))

        # ── Logo ───────────────────────────────────────────────────────────
        logo_source = Printing::Config.receipt_logo_url
        if logo_source.present?
          doc.align(:center)
          doc.logo(logo_source)
          doc.blank
        end

        # ── Header ─────────────────────────────────────────────────────────
        doc.align(:center)
        doc.bold
        doc.text(restaurant)
        doc.bold(false)
        doc.text(@order.order_number)
        doc.text(@order.created_at.strftime("%d/%m/%Y %I:%M %p"))
        doc.bold
        doc.double_height
        doc.text(@order.fulfillment_summary)
        doc.double_height(false)
        doc.bold(false)
        if @order.customer
          doc.blank
          doc.text(@order.customer.display_name) if @order.customer.name.present?
          @order.customer.contact_phones.each { |p| doc.text(p) }
        end
        doc.blank

        # ── Items table ────────────────────────────────────────────────────
        doc.align(:left)
        doc.separator
        doc.row3(I18n.t("printing.receipt.item"), I18n.t("printing.receipt.qty"), I18n.t("printing.receipt.price"))
        doc.separator

        @order.order_items.includes(:order_item_modifiers, :menu_item, :combo).each do |item|
          doc.row3(item.display_name, item.quantity.to_s, format_money(item.line_total_cents))
          item.order_item_modifiers.each do |modifier|
            doc.modifier_text("+ #{modifier.name}")
          end
          doc.modifier_text(item.notes) if item.notes.present?
          doc.separator
        end

        # ── Totals ─────────────────────────────────────────────────────────
        doc.blank
        doc.row(I18n.t("printing.receipt.subtotal"), format_money(@order.subtotal_cents))
        if @order.discount_cents.positive?
          doc.row(I18n.t("printing.receipt.discount"), "-#{format_money(@order.discount_cents)}")
        end
        doc.row(I18n.t("printing.receipt.tip"), format_money(@order.tip_cents)) if @order.tip_cents.positive?

        doc.bold
        doc.row(I18n.t("printing.receipt.total"), format_money(@order.total_cents))
        doc.bold(false)
        doc.rule

        if @order.customer
          doc.blank
          doc.align(:center)
          doc.text(I18n.t("printing.receipt.loyalty", points: @order.customer.loyalty_points))
        end

        doc.blank
        doc.align(:center)
        footer = Printing::Config.receipt_footer_text.presence || I18n.t("printing.receipt.thank_you")
        doc.text(footer)
        doc.blank(4)
        doc.cut
        doc
      end

      def line_width
        @printer.paper_width == "58mm" ? 32 : 42
      end

      def format_money(cents)
        Money.new(cents.to_i).format(symbol: false)
      end

      def compose_payments(doc)
        payments = @order.payments.where(status: "completed").order(:created_at)
        return if payments.none?

        doc.text(I18n.t("printing.receipt.payments"))
        payments.each do |payment|
          label = I18n.t("payment.methods.#{payment.payment_method}", default: payment.payment_method.humanize)
          doc.row("  #{label}", format_money(payment.amount_cents))
        end
      end

      def compose_change(doc)
        cash_payments = @order.payments.where(payment_method: "cash", status: "completed")
        return unless cash_payments.one?

        change = cash_payments.first.amount_cents - @order.total_cents
        return unless change.positive?

        doc.row(I18n.t("printing.receipt.change"), format_money(change))
      end
    end
  end
end
