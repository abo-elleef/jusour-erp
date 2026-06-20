# frozen_string_literal: true

module Admin
  class PrintDebugController < BaseController
    before_action :require_debug_mode

    def show
      @order = Order.unscoped.find(params[:order_id])
      printer = Printer.default_for("receipt", location: @order.location) ||
                Printer.new(paper_width: "80mm", name: "(default)")

      @debug = Printing::Escpos::ReceiptBuilder.new(@order, printer: printer).build_debug
    end

    private

    def require_debug_mode
      return if ENV["PRINT_DEBUG"] == "true"

      redirect_to admin_root_path, alert: "Set PRINT_DEBUG=true to enable print preview."
    end
  end
end
