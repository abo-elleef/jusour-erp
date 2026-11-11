# frozen_string_literal: true

module Printing
  # What the "prints failed" panel shows: failures grouped by printer and cause, so
  # the cashier fixes one problem (the bar printer is off) instead of reading eleven
  # rows that all say the same thing. Each group carries what to check and a ready
  # report for support. Kitchen / pickup groups come first: a missed receipt is
  # an annoyance, a missed kitchen ticket is food nobody cooks.
  class FailedPrintsSummary
    include Rails.application.routes.url_helpers

    PRODUCTION_TYPES = %w[kitchen bar expo pick_station station].freeze

    # context: { branch:, register:, cashier: } — names only, for the support report.
    def initialize(logs, context: {}, support_url: nil)
      @logs = logs.to_a
      @context = context
      @support_url = support_url
    end

    def as_json(*)
      groups = @logs.group_by { |log| group_key(log) }
                    .map { |(_, reason), logs| group_json(logs, reason) }
                    .sort_by { |g| [g[:production] ? 0 : 1, -g[:latest_failed_ts]] }
      {
        count: @logs.size,
        production_count: @logs.count { |l| production?(l) },
        support_url: @support_url,
        groups: groups
      }
    end

    private

    # A dead print agent is the register's problem, not any one printer's: every
    # ticket it touched fails the same way. One card for all of them; every other
    # cause is about a particular printer.
    def group_key(log)
      reason = log.failure_reason_key
      reason == :agent_unreachable ? [nil, reason] : [log.printer_id, reason]
    end

    def group_json(logs, reason)
      logs = logs.sort_by(&:updated_at).reverse
      agent = reason == :agent_unreachable
      printer = agent ? nil : logs.first.printer
      {
        key: agent ? "agent" : "#{printer&.id || 'none'}-#{reason}",
        printer: if agent
                   I18n.t("printing.status.agent_group")
                 else
                   printer&.name || I18n.t("printing.status.no_printer_name")
                 end,
        host: printer_address(printer),
        reason_key: reason,
        reason: I18n.t("printing.status.reasons.#{reason}"),
        checks: Array(I18n.t("printing.status.checks.#{reason}", default: [])),
        production: logs.any? { |l| production?(l) },
        latest_failed_ts: logs.first.updated_at.to_i,
        title: I18n.t("printing.status.tickets_failed", count: logs.size),
        jobs: logs.map { |l| job_json(l) },
        report: report_text(logs, reason)
      }
    end

    def job_json(log)
      order = log.order
      {
        id: log.id,
        print_type: log.print_type,
        ticket: ticket_label(log),
        printer: log.printer&.name,
        production: production?(log),
        order_number: order&.order_number,
        order_url: order ? pos_order_path(order) : nil,
        ordered_at: display_time(order&.created_at),
        failed_at: display_time(log.updated_at),
        error: log.error_message
      }
    end

    # Plain text, one fact per line: it is pasted into WhatsApp as is.
    def report_text(logs, reason)
      r = ->(key) { I18n.t("printing.status.report.#{key}") }
      lines = ["⚠️ #{r[:title]}"]
      lines << "#{r[:branch]}: #{@context[:branch]}" if @context[:branch].present?
      lines << "#{r[:register]}: #{@context[:register]}" if @context[:register].present?
      lines << "#{r[:cashier]}: #{@context[:cashier]}" if @context[:cashier].present?
      lines << "#{r[:sent_at]}: #{I18n.l(Time.current, format: :short)}"
      logs.map(&:printer).uniq.each do |printer|
        lines << "#{r[:printer]}: #{[printer&.name, printer_address(printer)].compact.join(' — ').presence || '—'}"
      end
      lines << "#{r[:problem]}: #{I18n.t("printing.status.reasons.#{reason}")}"
      lines << "#{r[:tickets]}:"
      logs.each do |log|
        order = log.order ? "##{log.order.order_number}" : "—"
        lines << "• #{order} #{ticket_label(log)} (#{log.printer&.name || '—'}) — #{display_time(log.updated_at)}"
      end
      errors = logs.map(&:error_message).compact.uniq
      lines << "#{r[:error]}: #{errors.join(' | ')}" if errors.any?
      lines.join("\n")
    end

    def ticket_label(log)
      I18n.t("printing.status.t_#{log.print_type}", default: log.print_type)
    end

    def printer_address(printer)
      return nil unless printer&.host.present?

      printer.usb? ? "USB #{printer.host}" : [printer.host, printer.port].compact.join(":")
    end

    def production?(log)
      PRODUCTION_TYPES.include?(log.print_type)
    end

    # Today's jobs show just the time; anything older shows the day too.
    def display_time(time)
      return nil unless time

      local = time.in_time_zone
      clock = I18n.l(local, format: :short_time)
      local.to_date == Time.zone.today ? clock : "#{local.strftime('%d/%m')} #{clock}"
    end
  end
end
