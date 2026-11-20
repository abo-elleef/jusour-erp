# frozen_string_literal: true

module Admin
  # Settings → Ticket categories (Bazzar slice G1): the list offered when a
  # ticket is opened, each with an optional default handler. Owner or
  # tickets:assign, and only where the distribution sales area exists.
  class TicketCategoriesController < BaseController
    before_action :require_ticket_area
    before_action :require_ticket_manager
    before_action :set_category, only: %i[edit update destroy]

    def index
      @categories = ::TicketCategory.ordered.includes(:default_handler)
      @ticket_counts = ::Ticket.group(:ticket_category_id).count
    end

    def new
      @category = ::TicketCategory.new(active: true, position: (::TicketCategory.maximum(:position) || -1) + 1)
      load_form_data
    end

    def create
      @category = ::TicketCategory.new(category_params)
      if @category.save
        redirect_to admin_ticket_categories_path, notice: t("tickets.categories.flash.created")
      else
        load_form_data
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      load_form_data
    end

    def update
      if @category.update(category_params)
        redirect_to admin_ticket_categories_path, notice: t("tickets.categories.flash.updated")
      else
        load_form_data
        render :edit, status: :unprocessable_entity
      end
    end

    # Only a category no ticket uses; others are switched off instead.
    def destroy
      if @category.deletable?
        @category.destroy
        redirect_to admin_ticket_categories_path, notice: t("tickets.categories.flash.deleted")
      else
        redirect_to admin_ticket_categories_path, alert: t("tickets.categories.flash.in_use")
      end
    end

    private

    def set_category
      @category = ::TicketCategory.find(params[:id])
    end

    def load_form_data
      @handlers = ::User.where(company_id: Current.company.id).active.order(:name)
    end

    def require_ticket_area
      return if ::Sales::OwnershipScope.applies_to?(Current.company)

      flash[:alert] = t("flash.feature_unavailable", default: "That feature isn't available for your business type.")
      redirect_to admin_root_path
    end

    def require_ticket_manager
      return if ::Ticket.manager?(current_user)

      flash[:alert] = t("flash.access_denied")
      redirect_to admin_root_path
    end

    def category_params
      permitted = params.require(:ticket_category).permit(:name, :name_ar, :active, :position, :default_handler_id)
      # Only someone in this company can be a default handler.
      handler_id = permitted[:default_handler_id].presence
      if handler_id && !::User.where(company_id: Current.company.id).exists?(id: handler_id)
        permitted[:default_handler_id] = nil
      end
      permitted
    end
  end
end
