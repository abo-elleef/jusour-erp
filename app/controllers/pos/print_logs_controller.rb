# frozen_string_literal: true

module Pos
  class PrintLogsController < ApplicationController
    layout "pos"

    before_action :require_pos_access!
    before_action :set_print_log, except: :pending

    def pending
      authorize PrintLog, :pending?
      location_id = session[:pos_location_id]
      logs = PrintLog.includes(:order, :printer)
                     .where(status: "pending")
                     .joins(:order)
                     .where(orders: { company_id: current_user.company_id })
      logs = logs.where(orders: { location_id: location_id }) if location_id.present?
      logs = logs.where("print_logs.created_at > ?", 2.hours.ago)
      render json: logs.map { |l| { id: l.id, order_id: l.order_id } }
    end

    def payload
      authorize @print_log, :payload?

      printer = @print_log.printer
      unless printer
        return render json: { error: t("printing.errors.no_printer") }, status: :unprocessable_entity
      end

      data = Printing::BuildPayloadService.call(
        order: @print_log.order,
        printer: printer,
        print_type: @print_log.print_type,
        host: params[:host],
        port: params[:port]
      )

      render json: data.merge(print_log_id: @print_log.id)
    end

    def confirm
      authorize @print_log, :confirm?

      status = params[:status].presence_in(PrintLog::STATUSES) || "failed"
      @print_log.update!(
        status: status,
        error_message: params[:error_message].presence
      )
      head :ok
    end

    private

    def require_pos_access!
      return if current_user&.can_access_pos?

      render json: { error: t("flash.pos_access") }, status: :forbidden
    end

    def set_print_log
      @print_log = PrintLog.includes(:order, :printer).find(params[:id])
    end
  end
end
