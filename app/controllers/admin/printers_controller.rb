# frozen_string_literal: true

module Admin
  class PrintersController < BaseController
    before_action :set_printer, only: %i[show edit update destroy test_print]

    def index
      authorize Printer

      scope = policy_scope(Printer)
      @q = scope.ransack(params[:q])
      @total_count = scope.count
      @active_count = scope.where(active: true).count
      @inactive_count = @total_count - @active_count
      @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
      @printers = @q.result.order(:printer_type, :name)
    end

    def show
      authorize @printer
      @recent_print_logs = @printer.print_logs.includes(:order).order(created_at: :desc).limit(10)
      return unless @printer.network? && Printing::Config.server_routing?

      @connection_check = Printing::Drivers::Network.check_connection(
        host: @printer.host,
        port: @printer.port || Printing::Drivers::Network::DEFAULT_PORT
      )
    end

    def new
      @printer = Printer.new(active: true, connection_type: "network", port: 9100, paper_width: "80mm")
      authorize @printer
    end

    def create
      @printer = Printer.new(printer_params)
      authorize @printer

      if @printer.save
        redirect_to admin_printer_path(@printer), notice: t("flash.printer.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @printer
    end

    def update
      authorize @printer

      if @printer.update(printer_params)
        redirect_to admin_printer_path(@printer), notice: t("flash.printer.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @printer
      @printer.destroy
      redirect_to admin_printers_path, notice: t("flash.printer.removed")
    end

    def test_print
      authorize @printer, :test_print?

      if @printer.usb?
        redirect_to admin_printer_path(@printer), alert: t("printing.errors.usb_not_supported")
        return
      end

      if Printing::Config.client_routing?
        redirect_to admin_printer_path(@printer), alert: t("printing.agent.use_agent_button")
        return
      end

      width = @printer.paper_width == "58mm" ? 32 : 42
      doc = Printing::Escpos::Document.new(width: width)
      doc.align(:center)
      doc.bold
      doc.text(Setting.get("restaurant_name", t("app.name")))
      doc.bold(false)
      doc.text(t("printing.test.title"))
      doc.text(@printer.name)
      doc.text(Time.current.strftime("%b %d, %Y %l:%M %p"))
      doc.blank(2)
      doc.cut

      Printing::Drivers::Network.print!(
        host: @printer.host,
        port: @printer.port || Printing::Drivers::Network::DEFAULT_PORT,
        data: doc.to_bytes
      )
      redirect_to admin_printer_path(@printer), notice: t("printing.test.sent")
    rescue Printing::Drivers::Network::Error => e
      redirect_to admin_printer_path(@printer), alert: e.message
    end

    private

    def set_printer
      @printer = Printer.find(params[:id])
    end

    def printer_params
      params.require(:printer).permit(
        :name, :printer_type, :connection_type, :host, :port, :location,
        :paper_width, :active, :is_default, :notes
      )
    end
  end
end
