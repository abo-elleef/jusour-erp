# frozen_string_literal: true

module Admin
  module Accounting
    # Month-end review of late penalties logged from the attendance grid.
    # Grouped by staff so managers can waive (delete) some before payroll.
    class LatePenaltiesController < BaseController
      before_action { require_feature!(:attendance) }
      include StaffLocationFilter

      def index
        @payroll_month = parse_payroll_month
        load_staff_location_filter
        staff = staff_scope
        adjustments = PayrollAdjustment.attendance_late
          .for_month(@payroll_month)
          .where(user_id: staff.map(&:id))
          .includes(:user, :recorded_by)
          .joins(:user)
          .order("users.name ASC, payroll_adjustments.happened_at ASC")

        @groups = adjustments.group_by(&:user)
        @finalized_user_ids = PayrollSnapshot.for_month(@payroll_month)
          .where(user_id: staff.map(&:id))
          .pluck(:user_id)
          .to_set
      end

      def destroy
        adjustment = scoped_late_penalty
        return redirect_to_index(alert: t("flash.late_penalty.not_found")) if adjustment.blank?

        authorize adjustment
        if PayrollSnapshot.exists?(user_id: adjustment.user_id, payroll_month: adjustment.payroll_month)
          return redirect_to_index(alert: t("flash.late_penalty.payroll_recorded"))
        end

        adjustment.destroy!
        redirect_to_index(notice: t("flash.payroll_adjustment.removed"))
      end

      private

      def scoped_late_penalty
        PayrollAdjustment.attendance_late
          .where(user_id: staff_scope.select(:id))
          .find_by(id: params[:id])
      end

      def staff_scope
        scope = scoped_staff.where("monthly_salary_cents > 0")
        apply_staff_location_filter(scope).order(:name)
      end

      def scoped_staff
        scope = User.where(company_id: Current.company.id).active
        return scope if current_user.all_locations?

        scope.joins(:user_locations)
          .where(user_locations: { location_id: current_user.location_ids })
          .distinct
      end

      def redirect_to_index(notice: nil, alert: nil)
        redirect_to admin_accounting_late_penalties_path(index_params), notice: notice, alert: alert
      end

      def index_params
        {
          payroll_month: params[:payroll_month].presence,
          location_id: params[:location_id].presence
        }.compact
      end
    end
  end
end
