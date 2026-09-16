# frozen_string_literal: true

module Admin
  module Accounting
    # Closing or switching a branch's own day is day-close work, gated by the
    # section permission — it used to be owner-only, which left managers looking at
    # a day they could not close and fetching the owner at midnight. Setting the
    # company-wide default start hour is fiscal configuration and stays with the
    # owner.
    class BusinessDaysController < BaseController
      before_action :require_owner!, only: :update_defaults

      def index
        @company_start_hour = BusinessDay.company_start_hour
        # Everyone who can reach this page can act on it; the section gate is the
        # authority, not the role name.
        @can_configure = current_user.can?("accounting:day_close")
        @branches = Location.active.branches.ordered.includes(:location_operating_days)
        @rows = @branches.map { |location| row_for(location) }
        @any_manual = @rows.any? { |row| row[:manual?] }
      end

      def update
        location = Location.active.branches.find(params[:location_id])
        previous_mode = BusinessDay.mode(location: location)

        attrs = {}
        if params.key?(:business_day_start_hour)
          hour = params[:business_day_start_hour].to_s.strip
          attrs[:business_day_start_hour] = hour.blank? ? nil : hour.to_i.clamp(0, 23)
        end

        if params[:business_day_mode].present? && BusinessDay::MODES.include?(params[:business_day_mode])
          attrs[:business_day_mode] = params[:business_day_mode]
        end

        location.assign_attributes(attrs)
        location.save!

        if previous_mode != "manual" && BusinessDay.manual?(location: location)
          BusinessDay.ensure_current_day!(location, user: current_user)
        end

        redirect_to admin_accounting_business_days_path,
              notice: t("flash.accounting.business_day_branch_updated", branch: location.name)
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_accounting_business_days_path,
              alert: e.record.errors.full_messages.to_sentence
      end

      def update_defaults
        hour = params[:business_day_start_hour].to_i.clamp(0, 23)
        Setting.set("business_day_start_hour", hour)
        redirect_to admin_accounting_business_days_path,
              notice: t("flash.accounting.business_day_defaults_updated")
      end

      def advance
        location = Location.active.branches.find(params[:location_id])
        result = ::Accounting::AdvanceBusinessDay.call(location: location, user: current_user)

        if result.success?
          redirect_to admin_accounting_business_days_path,
                notice: t("flash.accounting.business_day_advanced",
                  branch: result.location.name,
                  from: l(result.from_date),
                  to: l(result.to_date))
        else
          redirect_to admin_accounting_business_days_path, alert: "#{location.name}: #{result.error}"
        end
      end

      def advance_all
        batch = ::Accounting::AdvanceBusinessDay.call_all(user: current_user)
        parts = []
        if batch.advanced.any?
          names = batch.advanced.map { |r| "#{r.location.name} → #{l(r.to_date)}" }.join("; ")
          parts << t("flash.accounting.business_day_advanced_many", list: names)
        end
        if batch.failed.any?
          fails = batch.failed.map { |r| "#{r.location.name}: #{r.error}" }.join("; ")
          parts << t("flash.accounting.business_day_blocked_many", list: fails)
        end
        if batch.failed.any? && batch.advanced.empty?
          redirect_to admin_accounting_business_days_path, alert: parts.join(" ")
        elsif batch.failed.any?
          redirect_to admin_accounting_business_days_path, notice: parts.join(" "),
                alert: t("flash.accounting.business_day_partial")
        else
          redirect_to admin_accounting_business_days_path,
                notice: parts.presence&.join(" ") || t("flash.accounting.business_day_none")
        end
      end

      private

      def require_owner!
        raise Pundit::NotAuthorizedError unless current_user.owner?
      end

      def row_for(location)
        open_day = LocationOperatingDay.current_for(location)
        open_drawers = CashDrawerSession.open.where(location_id: location.id).includes(:user)
        {
          location: location,
          manual?: BusinessDay.manual?(location: location),
          business_date: BusinessDay.today(location: location),
          start_hour: BusinessDay.start_hour(location: location),
          start_hour_overridden: location.business_day_start_hour_overridden?,
          open_day: open_day,
          open_drawer_count: open_drawers.size,
          open_drawer_names: open_drawers.map { |s| s.user.name }.uniq,
          clear?: open_drawers.none?
        }
      end
    end
  end
end
