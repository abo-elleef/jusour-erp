# frozen_string_literal: true

module Admin
  class PrintAgentController < BaseController
    def test_payload
      authorize Printer, :index?

      printer = Printer.find(params[:printer_id])
      authorize printer, :test_print?

      width = printer.paper_width == "58mm" ? 32 : 42
      doc = Printing::Escpos::Document.new(width: width)
      doc.align(:center)
      doc.bold
      doc.text(Setting.get("restaurant_name", t("app.name")))
      doc.bold(false)
      doc.text(t("printing.test.title"))
      doc.text(printer.name)
      doc.text(Time.current.strftime("%b %d, %Y %l:%M %p"))
      doc.blank(2)
      doc.cut

      render json: {
        host: printer.host,
        port: printer.port || Printing::Drivers::Network::DEFAULT_PORT,
        printer_name: printer.name,
        data_base64: Base64.strict_encode64(doc.to_bytes)
      }
    end
  end
end
