# frozen_string_literal: true

module Admin
  module Sales
    # Rep-logged timeline entries (call/whatsapp/email/meeting/note) on a lead.
    # Stage/assignment entries are logged by Lead itself (see #change_stage!,
    # #reassign!, #convert!, #mark_lost!), never created here.
    class LeadActivitiesController < Admin::BaseController
      before_action { require_feature!(:leads) }
      before_action :require_leads_manage
      before_action :set_lead

      def create
        @activity = @lead.lead_activities.build(activity_params)
        @activity.user = current_user

        if @activity.save
          redirect_to admin_sales_lead_path(@lead), notice: t("sales.leads.flash.activity_logged")
        else
          redirect_to admin_sales_lead_path(@lead), alert: @activity.errors.full_messages.to_sentence
        end
      end

      private

      def set_lead
        @lead = Lead.find(params[:lead_id])
      end

      def require_leads_manage
        return if current_user.can?("leads:manage")

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_sales_leads_path
      end

      def activity_params
        params.require(:lead_activity).permit(:activity_type, :note, :occurred_at)
          .merge(activity_type: params.dig(:lead_activity, :activity_type).to_s.presence_in(LeadActivity::LOGGABLE_TYPES))
      end
    end
  end
end
