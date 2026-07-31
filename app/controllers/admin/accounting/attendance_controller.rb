# frozen_string_literal: true

module Admin
  module Accounting
    # Monthly attendance grid (staff × days). Cells are P/O/A/X; blank = unpaid.
    # Edits autosave one batch at a time via #update and return refreshed per-user
    # summaries so the pay column stays live.
    class AttendanceController < BaseController
      def index
        @payroll_month = parse_month
        @filter_locations = filterable_locations
        @location_filter = params[:location_id].to_s
        @company_wide_staff = @location_filter == COMPANY_WIDE_FILTER
        @location = selected_location
        @days = (@payroll_month.beginning_of_month..@payroll_month.end_of_month).to_a
        @statuses = AttendanceStatus.active.ordered.to_a
        @staff = staff_scope

        rows = StaffAttendance.for_month(@payroll_month)
          .where(user_id: @staff.map(&:id))
          .includes(:attendance_status)
        @cells = rows.each_with_object({}) { |r, h| h[[r.user_id, r.date]] = r.attendance_status }

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

      def update
        month = nil
        affected = []

        (params[:cells] || []).each do |cell|
          user = scoped_staff.find_by(id: cell[:user_id])
          next if user.blank?

          date = cell[:date].to_date
          month ||= date.beginning_of_month
          affected << user
          apply_cell(user, date, cell[:symbol].to_s.strip)
        end

        month ||= parse_month
        summaries = affected.uniq.index_with do |user|
          summary_json(::Accounting::AttendanceMonthService.new(user, month).call)
            .merge(counts: symbol_counts_for(user, month))
        end.transform_keys(&:id)

        render json: { ok: true, summaries: summaries }
      rescue ActiveRecord::RecordInvalid, Date::Error, ArgumentError => e
        render json: { ok: false, error: e.message }, status: :unprocessable_entity
      end

      private

      COMPANY_WIDE_FILTER = "company_wide"

      def apply_cell(user, date, symbol)
        if symbol.blank?
          user.staff_attendances.where(date: date).destroy_all
          return
        end

        status = AttendanceStatus.active.find_by(symbol: symbol)
        return if status.nil?

        record = user.staff_attendances.find_or_initialize_by(date: date)
        record.attendance_status = status
        record.recorded_by = current_user
        record.save!
      end

      def staff_scope
        scope = scoped_staff.where("monthly_salary_cents > 0")
        if @company_wide_staff
          scope = scope.where(all_locations: true)
        elsif @location
          scope = scope.joins(:user_locations)
            .where(user_locations: { location_id: @location.id })
            .distinct
        end
        scope.order(:name)
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

      def filterable_locations
        Location.active.ordered.where(id: current_user.accessible_location_ids)
      end

      def selected_location
        return if @location_filter.blank? || @company_wide_staff

        filterable_locations.find_by(id: @location_filter)
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
          if adj.kind == "bonus" && adj.unit_type == "overtime"
            bucket[:overtime_hours] = adj.overtime_hours
          elsif adj.kind == "penalty" && DAY_PENALTY_UNITS.include?(adj.unit_type)
            bucket[:penalty_unit] = adj.unit_type
          end
        end
        map
      end

      def upsert_overtime_bonus(user, date, month, hours)
        hours = hours.to_d
        adj = user.payroll_adjustments.find_or_initialize_by(kind: "bonus", unit_type: "overtime", happened_at: date)
        if hours.positive?
          adj.assign_attributes(payroll_month: month, overtime_hours: hours, recorded_by: current_user)
          adj.save!
        elsif adj.persisted?
          adj.destroy!
        end
      end

      def upsert_penalty(user, date, month, unit)
        adj = user.payroll_adjustments.where(kind: "penalty", happened_at: date, unit_type: DAY_PENALTY_UNITS).first
        if DAY_PENALTY_UNITS.include?(unit)
          adj ||= user.payroll_adjustments.build(kind: "penalty", happened_at: date)
          adj.assign_attributes(unit_type: unit, payroll_month: month, recorded_by: current_user)
          adj.save!
        elsif adj
          adj.destroy!
        end
      end

      def day_state(user, date)
        ot = user.payroll_adjustments.find_by(kind: "bonus", unit_type: "overtime", happened_at: date)
        pen = user.payroll_adjustments.where(kind: "penalty", happened_at: date, unit_type: DAY_PENALTY_UNITS).first
        { overtime_hours: ot&.overtime_hours&.to_f, penalty_unit: pen&.unit_type }
      end

      def format_days(value)
        helpers.number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
      end

      def parse_month
        if params[:payroll_month].present?
          Date.parse("#{params[:payroll_month]}-01")
        else
          Date.current.beginning_of_month
        end
      rescue ArgumentError
        Date.current.beginning_of_month
      end
    end
  end
end
