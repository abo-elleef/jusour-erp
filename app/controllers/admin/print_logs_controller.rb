# frozen_string_literal: true

module Admin
  # Every print job across all branches, so failures can be found after the POS
  # "prints failed" pill has dropped them (it only shows one branch, last 12 hours).
  class PrintLogsController < BaseController
    before_action :set_print_log, only: %i[retry handle]

    # What the status filter offers. "unresolved" (the default) is a failed job that
    # nobody reprinted afterwards — the ones that may still be missing on paper.
    STATUS_FILTERS = %w[unresolved failed handled pending sent skipped all].freeze
    DEFAULT_STATUS = "unresolved"
    DEFAULT_DAYS = 7

    # Sortable columns -> SQL. Whitelisted: the key comes from the URL.
    INDEX_SORTS = {
      "created_at" => "print_logs.created_at",
      "branch"     => "(SELECT locations.name FROM locations " \
                      "WHERE locations.id = COALESCE(orders.location_id, cash_drawer_sessions.location_id))",
      "printer"    => "(SELECT printers.name FROM printers WHERE printers.id = print_logs.printer_id)",
      "print_type" => "print_logs.print_type",
      "status"     => "print_logs.status"
    }.freeze
    INDEX_DEFAULT_SORT = "created_at"
    INDEX_DEFAULT_DIRECTION = "desc"

    def index
      authorize PrintLog

      @status = STATUS_FILTERS.include?(params[:status]) ? params[:status] : DEFAULT_STATUS
      @from = parse_date(params[:from]) || DEFAULT_DAYS.days.ago.to_date
      @to = parse_date(params[:to]) || Time.zone.today
      @location_id = params[:location_id].presence
      @printer_id = params[:printer_id].presence
      @print_type = PrintLog::PRINT_TYPES.include?(params[:print_type]) ? params[:print_type] : nil

      base = filtered_scope
      @counts = {
        "unresolved" => base.where(status: "failed").unresolved.count,
        "failed" => base.where(status: "failed").count,
        "handled" => base.where(status: "handled").count,
        "all" => base.count
      }

      scope = apply_status(base).includes(:printer, :workstation, order: :location, cash_drawer_session: :location)
      @sort = INDEX_SORTS.key?(params[:sort].to_s) ? params[:sort].to_s : INDEX_DEFAULT_SORT
      @direction = %w[asc desc].include?(params[:dir].to_s) ? params[:dir].to_s : INDEX_DEFAULT_DIRECTION
      scope = scope.order(Arel.sql("#{INDEX_SORTS[@sort]} #{@direction} NULLS LAST, print_logs.created_at DESC"))

      @pagy, @print_logs = pagy(:offset, scope, limit: 50)
      @resolved_ids = resolved_ids(@print_logs)
      @filtered = @location_id || @printer_id || @print_type || params[:from].present? || params[:to].present?
      @locations = Location.order(:name)
      @printers = Printer.order(:name)
    end

    # Puts the job back in the queue; the branch's open register prints it.
    def retry
      authorize @print_log, :manage?

      if @print_log.requeue!
        respond_row(notice: t("print_logs.flash.retried"))
      else
        respond_row(alert: t("print_logs.flash.not_failed"))
      end
    end

    # Someone dealt with the ticket by hand; it leaves the unresolved list.
    def handle
      authorize @print_log, :manage?

      if @print_log.status == "failed"
        @print_log.update!(status: "handled")
        respond_row(notice: t("print_logs.flash.handled"))
      else
        respond_row(alert: t("print_logs.flash.not_failed"))
      end
    end

    private

    def set_print_log
      @print_log = policy_scope(PrintLog).find(params[:id])
    end

    def filtered_scope
      scope = policy_scope(PrintLog)
              .where(print_logs: { created_at: @from.beginning_of_day..@to.end_of_day })
      if @location_id
        scope = scope.where("COALESCE(orders.location_id, cash_drawer_sessions.location_id) = ?", @location_id)
      end
      scope = scope.where(printer_id: @printer_id) if @printer_id
      scope = scope.where(print_type: @print_type) if @print_type
      scope
    end

    def apply_status(scope)
      case @status
      when "unresolved" then scope.where(status: "failed").unresolved
      when "all" then scope
      else scope.where(status: @status)
      end
    end

    # Failed jobs on this page that were reprinted later, so the row can say so.
    def resolved_ids(logs)
      failed_ids = logs.select { |l| l.status == "failed" }.map(&:id)
      return Set.new if failed_ids.empty?

      Set.new(failed_ids) - PrintLog.where(id: failed_ids).unresolved.pluck(:id)
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    # Replace just the row, so the page keeps its scroll position.
    def respond_row(notice: nil, alert: nil)
      @print_log.reload
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(helpers.dom_id(@print_log),
                                 partial: "admin/print_logs/row",
                                 locals: { log: @print_log, resolved: false }),
            turbo_stream.append("toast-container", partial: "shared/toast",
                                                   locals: { message: notice || alert, type: notice ? :notice : :alert })
          ]
        end
        format.html { redirect_back fallback_location: admin_print_logs_path, notice: notice, alert: alert }
      end
    end
  end
end
