# frozen_string_literal: true

module Admin
  module Sales
    # The distributor's sales funnel — prospects tracked from first contact
    # through to converting into a real Customer (see Lead#convert!) or dropping
    # out (Lead#mark_lost!). Gated on its own `leads` feature + `leads:*`
    # permissions rather than BaseController's ar_credit_sales/customers:manage,
    # since a company could reasonably want a pipeline without full credit sales.
    class LeadsController < Admin::BaseController
      before_action { require_feature!(:leads) }
      before_action :require_leads_view
      before_action :require_leads_manage, only: %i[new create edit update destroy convert mark_lost reassign change_stage]
      before_action :set_lead, only: %i[show edit update destroy convert mark_lost reassign change_stage]

      def index
        @stage = params[:stage].presence_in(Lead::STAGES)
        @due_only = ActiveModel::Type::Boolean.new.cast(params[:due_only])
        @assigned_user_id = params[:assigned_user_id].presence
        @sort = params[:sort].presence_in(Lead::INDEX_SORTABLE_COLUMNS) || Lead::INDEX_DEFAULT_SORT
        @direction = params[:dir].presence_in(%w[asc desc]) || Lead::INDEX_DEFAULT_SORT_DIRECTION

        base = Lead.all
        base = base.where(location_id: current_user.accessible_location_ids) unless current_user.all_locations?
        base = base.where(assigned_user_id: @assigned_user_id) if @assigned_user_id

        # Tab/checkbox counts always reflect the location/assignee filter but not
        # the stage/due-only selection itself, so switching them doesn't look like
        # data vanished.
        @all_count = base.count
        @due_today_count = base.due_for_follow_up.count
        @stage_counts = base.group(:stage).count

        scope = base.includes(:assigned_user, :location)
        scope = scope.where(stage: @stage) if @stage
        # Independent of stage — "due for follow-up" is a date condition, not a
        # pipeline status, so it can narrow whichever stage (or "All") is active.
        scope = scope.where(next_follow_up_at: ..Date.current) if @due_only
        scope = apply_sort(scope)

        @pagy, @leads = pagy(:offset, scope, limit: 50)
        @assignable_users = assignable_users
      end

      def show
        # LeadActivity.new (not @lead.lead_activities.build) so this unsaved form
        # object doesn't get cached into @lead.lead_activities' in-memory target —
        # the timeline below iterates that same association and would otherwise
        # render this blank, unvalidated record alongside the real ones.
        @activity = LeadActivity.new(lead: @lead)
        @assignable_users = assignable_users
      end

      def new
        @lead = Lead.new(assigned_user_id: current_user.id)
        load_form_data
      end

      def create
        @lead = Lead.new(lead_params)
        @lead.created_by = current_user

        if @lead.save
          redirect_to admin_sales_lead_path(@lead), notice: t("sales.leads.flash.created")
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        load_form_data
      end

      def update
        if @lead.update(lead_params)
          redirect_to admin_sales_lead_path(@lead), notice: t("sales.leads.flash.updated")
        else
          load_form_data
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @lead.destroy
        redirect_to admin_sales_leads_path, notice: t("sales.leads.flash.deleted")
      end

      def convert
        customer = @lead.convert!(by: current_user, customer_type: params[:customer_type].presence || "regular")
        redirect_to new_admin_sales_customer_invoice_path(customer_id: customer.id),
          notice: t("sales.leads.flash.converted", name: customer.name)
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_sales_lead_path(@lead), alert: t("sales.leads.flash.convert_failed", error: e.message)
      end

      def change_stage
        @lead.change_stage!(params[:stage], by: current_user)
        redirect_to admin_sales_lead_path(@lead), notice: t("sales.leads.flash.stage_changed")
      rescue ArgumentError, ActiveRecord::RecordInvalid => e
        redirect_to admin_sales_lead_path(@lead), alert: e.message
      end

      def mark_lost
        @lead.mark_lost!(by: current_user, lost_reason: params[:lost_reason], lost_reason_note: params[:lost_reason_note])
        redirect_to admin_sales_lead_path(@lead), notice: t("sales.leads.flash.marked_lost")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_sales_lead_path(@lead), alert: e.message
      end

      def reassign
        new_assignee = assignable_users.find_by(id: params[:assigned_user_id])
        if new_assignee
          @lead.reassign!(to: new_assignee, by: current_user)
          redirect_to admin_sales_lead_path(@lead), notice: t("sales.leads.flash.reassigned")
        else
          redirect_to admin_sales_lead_path(@lead), alert: t("sales.leads.flash.reassign_failed")
        end
      end

      private

      def set_lead
        @lead = Lead.find(params[:id])
      end

      def load_form_data
        @locations = Location.active.ordered.where(id: current_user.accessible_location_ids)
        @assignable_users = assignable_users
      end

      def assignable_users
        User.where(company_id: Current.company.id).active.order(:name)
      end

      def apply_sort(scope)
        if @sort == "assigned_user"
          scope.left_joins(:assigned_user).order("users.name #{@direction}")
        else
          scope.order(@sort => @direction)
        end
      end

      def require_leads_view
        return if current_user.can?("leads:view")

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_root_path
      end

      def require_leads_manage
        return if current_user.can?("leads:manage")

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_sales_leads_path
      end

      def lead_params
        params.require(:lead).permit(
          :name, :phone, :phone_secondary, :email, :source, :location_id,
          :assigned_user_id, :next_follow_up_at, :notes
        )
      end
    end
  end
end
