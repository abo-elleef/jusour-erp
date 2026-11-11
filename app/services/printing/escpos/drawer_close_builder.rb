# frozen_string_literal: true

module Printing
  module Escpos
    # The slip a cashier and the shift manager sign when a drawer is counted and
    # closed. Figures come from the same SessionSalesSummary as the count screen and
    # the drawer details page, and from the numbers stored on the drawer at close, so
    # the slip, the screen and the books cannot disagree.
    class DrawerCloseBuilder
      def initialize(session, printer:, reprint: false)
        @session = session
        @printer = printer
        @reprint = reprint
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
        calculator = ::Accounting::SessionSalesSummary.new(@session)
        summary = calculator.call
        refunded_cash = calculator.payments.select { |p| p.payment_method == "cash" }.sum(&:refunded_amount_cents)

        doc.align(:center)
        doc.bold
        doc.text(@session.company.receipt_name(location: @session.location))
        doc.double_height
        doc.text(I18n.t("printing.drawer_close.title"))
        doc.double_height(false)
        doc.bold(false)
        if @reprint
          doc.bold
          doc.text("*** #{I18n.t('printing.drawer_close.reprint')} ***")
          doc.bold(false)
        end
        doc.blank

        doc.align(:left)
        doc.row(I18n.t("printing.drawer_close.branch"), @session.location&.name.to_s)
        doc.row(I18n.t("printing.drawer_close.cashier"), @session.user.name.to_s)
        doc.row(I18n.t("printing.drawer_close.drawer"), @session.treasury&.name.to_s)
        doc.row(I18n.t("printing.drawer_close.date"), @session.session_date.strftime("%d/%m/%Y"))
        doc.row(I18n.t("printing.drawer_close.opened"), time(@session.created_at))
        doc.row(I18n.t("printing.drawer_close.closed"), @session.counted_cash_cents.nil? ? "-" : time(@session.updated_at))
        doc.separator

        doc.row(I18n.t("printing.drawer_close.opening_float"), money(summary.opening_float_cents))
        doc.row(I18n.t("payment.methods.cash"), money(summary.cash_cents))
        doc.row(I18n.t("payment.methods.instapay"), money(summary.instapay_cents))
        doc.row(I18n.t("payment.methods.vodafone_cash"), money(summary.vodafone_cash_cents))
        doc.bold
        doc.row(I18n.t("printing.drawer_close.total_sales"),
                money(summary.cash_cents + summary.instapay_cents + summary.vodafone_cash_cents))
        doc.bold(false)
        # Information only: refunded payments are already left out of the figures above.
        doc.row(I18n.t("printing.drawer_close.refunded_cash"), money(refunded_cash)) if refunded_cash.positive?
        doc.separator

        doc.row(I18n.t("printing.drawer_close.expected"), money(@session.expected_cash_cents))
        doc.bold
        doc.row(I18n.t("printing.drawer_close.counted"), money(@session.counted_cash_cents))
        doc.row(I18n.t("printing.drawer_close.variance"), money(@session.variance_cents))
        doc.bold(false)
        if @session.deposit_treasury && @session.counted_cash_cents
          doc.row(I18n.t("printing.drawer_close.banked_to"), @session.deposit_treasury.name.to_s)
        end
        doc.rule

        signature_block(doc, I18n.t("printing.drawer_close.cashier_signature"))
        signature_block(doc, I18n.t("printing.drawer_close.manager_signature"))

        doc.align(:center)
        doc.text("#{I18n.t('printing.drawer_close.printed')} #{time(Time.current)}")
        doc.blank(4)
        doc.cut
        doc
      end

      def signature_block(doc, label)
        doc.align(:left)
        doc.blank
        doc.text(label)
        doc.blank
        doc.text("_" * (line_width - 4))
      end

      def line_width
        @printer.paper_width == "58mm" ? 32 : 42
      end

      def money(cents)
        return "-" if cents.nil?

        Money.new(cents.to_i).format(symbol: false)
      end

      def time(value)
        value.in_time_zone.strftime("%d/%m/%Y %I:%M %p")
      end
    end
  end
end
