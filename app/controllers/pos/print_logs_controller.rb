# frozen_string_literal: true

module Pos
  class PrintLogsController < ApplicationController
    layout "pos"

    before_action :require_pos_access!
    before_action :set_print_log, except: %i[pending failed]

    def pending
      authorize PrintLog, :pending?
      # Recent by last touch, so a retried job is recovered too. A pending job is only
      # ever touched when it is queued or requeued.
      logs = branch_logs.where(status: "pending")
                        .where("print_logs.updated_at > ?", 2.hours.ago)
                        .claimable_by(params[:client_id])

      render json: logs.map { |l| { id: l.id, order_id: l.order_id } }
    end

    # Jobs that failed and still need a person: feeds the "N prints failed" pill.
    def failed
      authorize PrintLog, :failed?
      logs = branch_logs.needs_attention.includes(:order).order("print_logs.updated_at DESC").limit(20)

      render json: {
        count: logs.size,
        jobs: logs.map do |l|
          { id: l.id, print_type: l.print_type, order_number: l.order&.order_number, error: l.error_message }
        end
      }
    end

    def retry
      authorize @print_log, :retry?

      @print_log.requeue!
      respond_to do |format|
        format.json { head :ok }
        format.html { redirect_back fallback_location: pos_path, notice: t("flash.pos.print_queued") }
      end
    end

    # Handing out the payload is what claims the job: the first register to ask gets
    # it, everyone else gets 409 and must not print. Asking again with the same
    # client id (a retry) is fine.
    def payload
      authorize @print_log, :payload?

      unless PrintLog.claim!(@print_log.id, params[:client_id])
        return render json: { error: "already_claimed" }, status: :conflict
      end

      printer = @print_log.printer
      unless printer
        return render json: { error: t("printing.errors.no_printer") }, status: :unprocessable_entity
      end

      data = Printing::BuildPayloadService.call(
        order: @print_log.order,
        drawer_session: @print_log.cash_drawer_session,
        reprint: Printing::PrintDrawerCloseService.reprint?(@print_log),
        printer: printer,
        print_type: @print_log.print_type,
        host: params[:host],
        port: params[:port]
      )

      render json: data.merge(print_log_id: @print_log.id)
    end

    def confirm
      authorize @print_log, :confirm?

      # A finished job stays as it was: a late "failed" from a retrying page must not
      # overwrite a "sent".
      return head :ok unless @print_log.status == "pending"

      status = params[:status].presence_in(PrintLog::STATUSES) || "failed"
      @print_log.update!(
        status: status,
        error_message: params[:error_message].presence
      )
      head :ok
    end

    private

    # Print jobs this register is responsible for: its company and branch; receipts
    # (and drawer slips that name a register) only for the register in use, production
    # tickets for the whole branch.
    def branch_logs
      location_id = session[:pos_location_id]
      workstation_id = session[:pos_workstation_id]
      company_id = current_user.company_id

      # A job belongs to an order or to a drawer session; either one places it in a
      # company and a branch.
      logs = PrintLog.left_joins(:order, :cash_drawer_session)
                     .where("orders.company_id = :c OR cash_drawer_sessions.company_id = :c", c: company_id)
      if location_id.present?
        logs = logs.where("orders.location_id = :l OR cash_drawer_sessions.location_id = :l", l: location_id)
      end
      if workstation_id.present?
        logs = logs.where(
          "(print_logs.print_type = 'receipt' AND orders.workstation_id = :w) OR " \
          "(print_logs.print_type = 'drawer_close' AND (print_logs.workstation_id IS NULL OR print_logs.workstation_id = :w)) OR " \
          "print_logs.print_type NOT IN ('receipt', 'drawer_close')",
          w: workstation_id
        )
      end
      logs
    end

    def require_pos_access!
      return if current_user&.can_access_pos?

      render json: { error: t("flash.pos_access") }, status: :forbidden
    end

    def set_print_log
      @print_log = PrintLog.includes(:order, :cash_drawer_session, :printer).find(params[:id])
    end
  end
end
