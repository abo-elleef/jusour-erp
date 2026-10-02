# frozen_string_literal: true

module Admin
  module Accounting
    # Monthly attendance grid (staff × days). Cells are P/O/A/X; blank = unpaid.
    # Edits autosave one batch at a time via #update and return refreshed per-user
    # summaries so the pay column stays live.
    class AttendanceController < BaseController
      before_action { require_feature!(:attendance) }
      include StaffLocationFilter

      def index
        @payroll_month = parse_payroll_month
        load_staff_location_filter
        @days = (@payroll_month.beginning_of_month..@payroll_month.end_of_month).to_a
        @statuses = AttendanceStatus.active.ordered.to_a
        @staff = staff_scope

        rows = StaffAttendance.for_month(@payroll_month)
          .where(user_id: @staff.map(&:id))
          .includes(:attendance_status, :recorded_by)
        # A cleared day keeps its row (nil status, for a stable audit trail) —
        # render it the same as no row at all.
        @cells = rows.each_with_object({}) { |r, h| h[[r.user_id, r.date]] = r.attendance_status if r.attendance_status }

        # Who recorded/last edited a cell, and when — only for roles trusted to
        # see that (owners/managers/super managers), not every role that can
        # merely view or log attendance.
        @can_view_attendance_audit = current_user.can?("attendance:audit")
        @cell_audit = @can_view_attendance_audit ? rows.index_by { |r| [r.user_id, r.date] } : {}

        @summaries = @staff.index_with do |user|
          ::Accounting::AttendanceMonthService.new(user, @payroll_month).call
        end

        @status_counts = @staff.index_with do |user|
          @statuses.to_h do |status|
            count = @days.count { |day| @cells[[user.id, day]]&.symbol == status.symbol }
            [status.symbol, count]
          end
        end

        @day_adjustments = day_adjustments_for(@staff, @days)
      end

      # Upsert/delete the per-day extra-hours bonus and late-penalty adjustments
      # for a single staff member (right-click popover on the grid). Same
      # PayrollAdjustment records as the user show page, so payroll stays in sync.
      def adjustment
        user = scoped_staff.find_by(id: params[:user_id])
        return render(json: { ok: false }, status: :not_found) if user.blank?

        date = params[:date].to_date
        month = date.beginning_of_month
        upsert_overtime_bonus(user, date, month, params[:overtime_hours])
        upsert_penalty(user, date, month, params[:penalty])

        render json: { ok: true }.merge(day_state(user, date))
      rescue ActiveRecord::RecordInvalid => e
        render json: { ok: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      rescue Date::Error, ArgumentError
        render json: { ok: false, error: "invalid" }, status: :unprocessable_entity
      end

      # Full change history for one staff member's one day (double-click on a
      # cell). Same trust level as the tooltip — owners/managers/super managers.
      def cell_history
        return render(json: { ok: false }, status: :forbidden) unless current_user.can?("attendance:audit")

        user = scoped_staff.find_by(id: params[:user_id])
        return render(json: { ok: false }, status: :not_found) if user.blank?

        date = params[:date].to_date
        record = user.staff_attendances.find_by(date: date)
        entries = record ? AuditLogEntry.where(record_type: "StaffAttendance", record_id: record.id)
          .includes(:user).order(created_at: :desc) : AuditLogEntry.none

        html = render_to_string(
          partial: "admin/accounting/attendance/cell_history",
          formats: [:html],
          locals: { entries: entries, title: "#{user.name} · #{l(date, format: :long)}" },
          layout: false
        )
        render json: { ok: true, html: html }
      rescue Date::Error, ArgumentError
        render json: { ok: false, error: "invalid" }, status: :unprocessable_entity
      end

      def update
        month = nil
        affected = []
        can_audit = current_user.can?("attendance:audit")
        audits = {}

        (params[:cells] || []).each do |cell|
          user = scoped_staff.find_by(id: cell[:user_id])
          next if user.blank?

          date = cell[:date].to_date
          month ||= date.beginning_of_month
          affected << user
          record = apply_cell(user, date, cell[:symbol].to_s.strip)
          audits["#{user.id}|#{date.iso8601}"] = audit_tooltip(record) if can_audit
        end

        month ||= parse_payroll_month
        summaries = affected.uniq.index_with do |user|
          summary_json(::Accounting::AttendanceMonthService.new(user, month).call)
            .merge(counts: symbol_counts_for(user, month))
        end.transform_keys(&:id)

        render json: { ok: true, summaries: summaries, audits: audits }
      rescue ActiveRecord::RecordInvalid, Date::Error, ArgumentError => e
        render json: { ok: false, error: e.message }, status: :unprocessable_entity
      end

      private

      # Returns the saved record (for the audit tooltip), or nil when there was
      # nothing to do (clearing an already-blank day) or the symbol didn't
      # match an active status.
      #
      # Clearing a day nils attendance_status on the SAME row rather than
      # destroying it — so the row's id (and its AuditLogEntry trail) stays
      # stable across set → clear → set again, instead of churning a new row
      # (and starting a fresh trail) every time.
      def apply_cell(user, date, symbol)
        new_status_id = symbol.present? ? AttendanceStatus.active.find_by(symbol: symbol)&.id : nil
        return nil if symbol.present? && new_status_id.nil? # unknown symbol — ignore

        record = user.staff_attendances.find_or_initialize_by(date: date)
        return nil if record.new_record? && new_status_id.nil? # nothing to clear

        was_new = record.new_record?
        record.attendance_status_id = new_status_id
        record.recorded_by = current_user
        record.save!

        log_attendance_change!(record, created: was_new) if was_new || record.saved_change_to_attendance_status_id?
        record
      end

      def log_attendance_change!(record, created:)
        AuditLogEntry.record!(
          action: created ? "create" : "update",
          record: record,
          user: current_user,
          changes_snapshot: { "attendance_status_id" => record.saved_change_to_attendance_status_id }
        )
      end

      def audit_tooltip(record)
        return nil if record.nil?

        t("accounting.attendance.recorded_by_tooltip",
          name: record.recorded_by&.name || t("accounting.attendance.unknown_recorder"),
          time: l(record.updated_at, format: :long_with_time))
      end

      def staff_scope
        scope = scoped_staff.where("monthly_salary_cents > 0")
        apply_staff_location_filter(scope).order(:name)
      end

      # Staff the current user may see/log for: everyone when global, otherwise
      # only staff assigned to a location the user is scoped to.
      def scoped_staff
        scope = company_users
        return scope if current_user.all_locations?

        scope.joins(:user_locations)
          .where(user_locations: { location_id: current_user.location_ids })
          .distinct
      end

      def company_users
        User.where(company_id: Current.company.id).active
      end

      def summary_json(result)
        {
          payable: format_days(result.payable_days),
          bonus: format_days(result.bonus_days),
          penalty: format_days(result.penalty_days)
        }
      end

      def symbol_counts_for(user, month)
        days = month.beginning_of_month..month.end_of_month
        tallies = user.staff_attendances.where(date: days)
          .joins(:attendance_status)
          .group("attendance_statuses.symbol")
          .count
        AttendanceStatus.active.ordered.to_h { |s| [s.symbol, tallies[s.symbol].to_i] }
      end

      DAY_PENALTY_UNITS = %w[quarter_day half_day full_day].freeze

      # { [user_id, date] => { overtime_hours:, penalty_unit: } } for the month.
      def day_adjustments_for(staff, days)
        map = {}
        PayrollAdjustment.where(user_id: staff.map(&:id), happened_at: days).find_each do |adj|
          key = [adj.user_id, adj.happened_at]
          bucket = (map[key] ||= {})
          if adj.kind == "bonus" && adj.unit_type == "overtime" && attendance_overtime_notes.include?(adj.notes)
            bucket[:overtime_hours] = adj.overtime_hours
          elsif adj.kind == "penalty" && DAY_PENALTY_UNITS.include?(adj.unit_type) && attendance_late_notes.include?(adj.notes)
            bucket[:penalty_unit] = adj.unit_type
          end
        end
        map
      end

      def upsert_overtime_bonus(user, date, month, hours)
        hours = hours.to_d
        adj = attendance_overtime_for(user, date)
        if hours.positive?
          adj ||= user.payroll_adjustments.build(kind: "bonus", unit_type: "overtime", happened_at: date)
          adj.assign_attributes(
            payroll_month: month,
            overtime_hours: hours,
            recorded_by: current_user,
            notes: adj.notes.presence || PayrollAdjustment.attendance_overtime_note
          )
          adj.save!
        elsif adj
          adj.destroy!
        end
      end

      def upsert_penalty(user, date, month, unit)
        adj = attendance_late_for(user, date)
        if DAY_PENALTY_UNITS.include?(unit)
          adj ||= user.payroll_adjustments.build(kind: "penalty", happened_at: date)
          adj.assign_attributes(
            unit_type: unit,
            payroll_month: month,
            recorded_by: current_user,
            notes: adj.notes.presence || PayrollAdjustment.attendance_late_note
          )
          adj.save!
        elsif adj
          adj.destroy!
        end
      end

      def day_state(user, date)
        ot = attendance_overtime_for(user, date)
        pen = attendance_late_for(user, date)
        { overtime_hours: ot&.overtime_hours&.to_f, penalty_unit: pen&.unit_type }
      end

      def attendance_late_for(user, date)
        user.payroll_adjustments.attendance_late.where(happened_at: date, unit_type: DAY_PENALTY_UNITS).first
      end

      def attendance_overtime_for(user, date)
        user.payroll_adjustments.attendance_overtime.find_by(happened_at: date)
      end

      def attendance_late_notes
        PayrollAdjustment.attendance_late_notes
      end

      def attendance_overtime_notes
        PayrollAdjustment.attendance_overtime_notes
      end

      def format_days(value)
        helpers.number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
      end
    end
  end
end
