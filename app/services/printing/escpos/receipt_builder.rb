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
        restaurant = @order.company.receipt_name(location: @order.location)

        # ── Logo ───────────────────────────────────────────────────────────
        doc.align(:center)
        doc.blank if doc.receipt_logo(location: @order.location, company: @order.company)

        # ── Header ─────────────────────────────────────────────────────────
        doc.align(:center)
        doc.bold
        doc.text(restaurant)
        doc.double_height
        doc.text(@order.display_number)
        doc.double_height(false)
        doc.bold(false)
        doc.text(@order.created_at.strftime("%d/%m/%Y %I:%M %p"))
        doc.bold
        doc.double_height
        doc.text(order_type_line)
        doc.double_height(false)
        doc.bold(false)
        if @order.customer
          doc.blank
          doc.text(@order.customer.display_name) if @order.customer.name.present?
          @order.customer.contact_phones.each { |p| doc.text(p) }
        end
        # Where the courier has to go — the order's own address, not the customer's list.
        doc.text(@order.delivery_address) if @order.delivery? && @order.delivery_address.present?
        doc.blank

        # ── Items table ────────────────────────────────────────────────────
        doc.align(:left)
        doc.separator
        doc.row3(I18n.t("printing.receipt.item"), I18n.t("printing.receipt.qty"), I18n.t("printing.receipt.price"))
        doc.separator

        @order.order_items.includes(:order_item_modifiers, :menu_item, :combo).each do |item|
          doc.row3(item.display_name, item.quantity.to_s, format_money(item.line_total_cents))
          # Every modifier and the note on one line, like the station tickets.
          TicketItemsTable.detail_lines(item, limit: detail_chars).each { |line| doc.modifier_text(line) }
          doc.separator
        end

        # ── Totals ─────────────────────────────────────────────────────────
        doc.blank
        doc.row(I18n.t("printing.receipt.subtotal"), format_money(@order.subtotal_cents))
        if @order.discount_cents.positive?
          doc.row(I18n.t("printing.receipt.discount"), "-#{format_money(@order.discount_cents)}")
        end
        doc.row(I18n.t("printing.receipt.tip"), format_money(@order.tip_cents)) if @order.tip_cents.positive?

        if @order.delivery_fee_cents.positive?
          # What the dispatcher takes from the driver on a cash delivery: the driver
          # keeps the delivery fee out of what they collected (see
          # Order#apply_delivery_fee!). It comes before the fee and the total, big and
          # boxed in, so it is the first number the dispatcher's eye lands on.
          if @order.delivery?
            doc.separator
            doc.row(I18n.t("printing.receipt.total_without_delivery"),
                    format_money(@order.total_cents - @order.delivery_fee_cents),
                    bold_label: true, bold_value: true)
            doc.separator
          end
          doc.row(I18n.t("printing.receipt.delivery_fee"), format_money(@order.delivery_fee_cents))
        end

        doc.bold
        doc.row(I18n.t("printing.receipt.total"), format_money(@order.total_cents))
        doc.bold(false)

        compose_payments(doc)
        compose_change(doc)
        doc.rule

        if @order.notes.present?
          doc.blank
          doc.align(:center)
          doc.bold
          doc.text(I18n.t("printing.receipt.order_notes"))
          doc.bold(false)
          doc.text(@order.notes)
          doc.rule
        end

        if @order.customer
          doc.blank
          doc.align(:center)
          doc.text(I18n.t("printing.receipt.loyalty", points: @order.customer.loyalty_points))
        end

        doc.blank
        doc.align(:center)
        footer = Printing::Config.receipt_footer_text.presence || I18n.t("printing.receipt.thank_you")
        doc.text(footer)
        doc.cut
        doc
      end

      # The item column is the right 54% of the paper (price and quantity take the
      # rest), so the detail line wraps sooner than on a kitchen ticket.
      RECEIPT_DETAIL_CHARS_RATIO = 0.5

      def detail_chars
        (line_width * RECEIPT_DETAIL_CHARS_RATIO).floor
      end

      def line_width
        @printer.paper_width == "58mm" ? 32 : 42
      end

      def format_money(cents)
        Money.new(cents.to_i).format(symbol: false)
      end

      def order_type_line
        "#{I18n.t('order.labels.order_type')}: #{@order.fulfillment_summary}"
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
