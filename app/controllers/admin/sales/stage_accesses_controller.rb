# frozen_string_literal: true

module Admin
  module Sales
    # The owner's role × invoice-stage grid: per role, which invoice stages its
    # members see and which ones notify them (Sales::StageAccess,
    # applied by Sales::StageVisibility). Owner only.
    class StageAccessesController < BaseController
      before_action :require_owner

      def show
        @roles = grid_roles
        @cells = ::Sales::StageAccess.where(role_id: @roles.map(&:id))
                                     .index_by { |a| [a.role_id, a.stage] }
      end

      # Saves the whole grid: every listed role gets one row per stage, so a
      # saved role is "configured" from then on. Notify only counts where the
      # role can also see the stage, and never for imported history.
      def update
        submitted = params.fetch(:grid, {}).to_unsafe_h
        roles = grid_roles

        ::Sales::StageAccess.transaction do
          roles.each do |role|
            ::Sales::StageAccess.where(role_id: role.id).delete_all
            CustomerInvoice::STAGES.each do |stage|
              cell = submitted.dig(role.id.to_s, stage) || {}
              can_see = cell["see"] == "1"
              notify = can_see && cell["notify"] == "1" && stage != "historical"
              ::Sales::StageAccess.create!(role: role, stage: stage, can_see: can_see, notify: notify)
            end
          end
        end

        redirect_to admin_sales_stage_access_path, notice: t("sales.stage_accesses.flash.updated")
      end

      private

      def require_owner
        return if current_user.owner?

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_sales_customer_invoices_path
      end

      # Every role that can open the sales area, except the owner's (who always
      # sees everything).
      def grid_roles
        Role.order(:name).reject { |r| r.key == "owner" }.select { |r| r.can?("customers:manage") }
      end
    end
  end
end
