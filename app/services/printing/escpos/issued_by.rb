# frozen_string_literal: true

module Printing
  module Escpos
    # Who sent a ticket to print, and from which register. Every print except the
    # customer receipt carries it, so a ticket in the kitchen can be traced back to
    # the cashier and the station that sent it.
    module IssuedBy
      private

      def compose_issued_by(doc, cashier:, station:)
        doc.align(:left)
        doc.row(I18n.t("printing.ticket.cashier"), cashier.presence || "-", padded: true)
        doc.row(I18n.t("printing.ticket.station"), station.presence || "-", padded: true)
      end
    end
  end
end
