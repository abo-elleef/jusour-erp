# frozen_string_literal: true

module Admin
  module Sales
    # Customer tickets — complaints and satisfaction cases (Bazzar slice G1).
    # Only where the distribution sales area exists (Sales::OwnershipScope
    # .applies_to?), so restaurants never see them; tickets:manage or
    # tickets:assign (or the owner) to get in. Which tickets a user sees is
    # Sales::OwnershipScope#tickets — someone else's ticket is a 404, as in
    # slice E. Tickets are opened from a customer or a customer invoice, so
    # `new` always carries a customer.
    class TicketsController < Admin::BaseController
      PAGE_SIZE = 25
      STATUS_FILTERS = (%w[active] + ::Ticket::STATUSES).freeze

      before_action :require_ticket_area
      before_action :require_ticket_access
      before_action :set_ticket, only: %i[show edit update change_status reassign]

      def index
        base = ownership.tickets(::Ticket.all)
        base = apply_filters(base)
        # Chips count within the other filters, so picking a status doesn't
        # make the rest look empty.
        @status_counts = base.group(:status).count
        @active_count = @status_counts.slice(*::Ticket::ACTIVE_STATUSES).values.sum
        @all_count = @status_counts.values.sum

        scope = @status == "active" ? base.active : base
        scope = scope.where(status: @status) if ::Ticket::STATUSES.include?(@status)
        scope = apply_sort(scope.includes(:customer, :assigned_user, :ticket_category, :customer_invoice))
        @pagy, @tickets = pagy(:offset, scope, limit: PAGE_SIZE)

        @assignees = staff
        @categories = ::TicketCategory.ordered
      end

      def show
        @comment = ::TicketComment.new(ticket: @ticket)
        @comments = @ticket.comments.includes(:user, images_attachments: :blob)
        @next_statuses = @ticket.next_statuses_for(current_user)
        @can_reassign = ::Ticket.manager?(current_user)
        @assignees = staff if @can_reassign
      end

      def new
        customer = visible_customers.find(params[:customer_id])
        @ticket = ::Ticket.new(customer: customer, priority: "normal")
        if params[:customer_invoice_id].present?
          @ticket.customer_invoice = ownership.invoices(customer.customer_invoices).find(params[:customer_invoice_id])
        end
        load_form_data
      end

      def create
        @ticket = ::Ticket.new(ticket_params)
        # Someone else's customer is a 404, as on the customer page.
        @ticket.customer = visible_customers.find(params.dig(:ticket, :customer_id))
        @ticket.opened_by = current_user
        # Choosing who works it is a manager's call; a rep's ticket goes to the
        # category's default handler (Ticket#default_assigned_user).
        @ticket.assigned_user = staff.find_by(id: params.dig(:ticket, :assigned_user_id)) if ::Ticket.manager?(current_user)
        restrict_links!

        if @ticket.save
          redirect_to admin_sales_ticket_path(@ticket), notice: t("tickets.flash.created", number: @ticket.display_number)
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        load_form_data
      end

      # Subject, description, category, priority, links and more images.
      # Status and assignee move only through their own actions, which write
      # the timeline entry.
      def update
        @ticket.assign_attributes(ticket_params.except(:images))
        restrict_links!
        new_images = Array(params.dig(:ticket, :images)).compact_blank
        @ticket.images.attach(new_images) if new_images.any?

        if @ticket.save
          redirect_to admin_sales_ticket_path(@ticket), notice: t("tickets.flash.updated")
        else
          load_form_data
          render :edit, status: :unprocessable_entity
        end
      end

      def change_status
        @ticket.change_status!(params[:status].to_s, by: current_user, note: params[:note])
        redirect_to admin_sales_ticket_path(@ticket),
          notice: t("tickets.flash.status_changed", status: t("tickets.statuses.#{@ticket.status}"))
      rescue ::Ticket::NotAllowed
        redirect_to admin_sales_ticket_path(@ticket), alert: t("tickets.flash.not_allowed")
      end

      def reassign
        to = staff.find_by(id: params[:assigned_user_id])
        @ticket.reassign!(to: to, by: current_user)
        redirect_to admin_sales_ticket_path(@ticket),
          notice: t("tickets.flash.reassigned", name: to&.name || t("tickets.unassigned"))
      rescue ::Ticket::NotAllowed
        redirect_to admin_sales_ticket_path(@ticket), alert: t("tickets.flash.not_allowed")
      end

      private

      def apply_filters(scope)
        @status = params[:status].presence_in(STATUS_FILTERS)
        @mine = ActiveModel::Type::Boolean.new.cast(params[:mine])
        @assigned_user_id = params[:assigned_user_id].presence
        @category_id = params[:category_id].presence
        @priority = params[:priority].presence_in(::Ticket::PRIORITIES)
        @customer_id = params[:customer_id].presence
        @query = params[:q].to_s.strip.presence
        @from = parse_date(:from)
        @to = parse_date(:to)
        @sort = params[:sort].presence_in(::Ticket::INDEX_SORTABLE_COLUMNS) || ::Ticket::INDEX_DEFAULT_SORT
        @direction = params[:dir].presence_in(%w[asc desc]) || ::Ticket::INDEX_DEFAULT_SORT_DIRECTION
        @filtered = [@mine, @assigned_user_id, @category_id, @priority, @customer_id, @query, @from, @to].any?(&:present?)

        scope = scope.where(assigned_user_id: current_user.id) if @mine
        scope = case @assigned_user_id
                when nil then scope
                when "none" then scope.where(assigned_user_id: nil)
                else scope.where(assigned_user_id: @assigned_user_id)
                end
        scope = scope.where(ticket_category_id: @category_id) if @category_id
        scope = scope.where(priority: @priority) if @priority
        if @customer_id
          scope = scope.where(customer_id: @customer_id)
          @customer = ::Customer.find_by(id: @customer_id)
        end
        scope = search(scope) if @query
        scope = scope.where(created_at: @from.beginning_of_day..) if @from
        scope = scope.where(created_at: ..@to.end_of_day) if @to
        scope
      end

      # Ticket number (T-0012 or 12), subject, or customer name / phone.
      def search(scope)
        number = @query[/\A\s*(?:T-?)?0*(\d+)\s*\z/i, 1]
        return scope.where(number: number.to_i) if number

        like = "%#{::Ticket.sanitize_sql_like(@query)}%"
        scope.left_joins(:customer).where(
          "tickets.subject ILIKE :q OR customers.name ILIKE :q OR customers.phone ILIKE :q", q: like
        )
      end

      def apply_sort(scope)
        case @sort
        when "customer"
          scope.left_joins(:customer).order(Arel.sql("customers.name #{@direction}"), number: :desc)
        when "assigned_user"
          scope.left_joins(:assigned_user).order(Arel.sql("users.name #{@direction} NULLS LAST"), number: :desc)
        when "priority"
          # urgent > normal > low, not alphabetical.
          order = ::Ticket::PRIORITIES.each_with_index.map { |p, i| "WHEN '#{p}' THEN #{i}" }.join(" ")
          scope.order(Arel.sql("CASE tickets.priority #{order} END #{@direction}"), number: :desc)
        when "status"
          order = ::Ticket::STATUSES.each_with_index.map { |s, i| "WHEN '#{s}' THEN #{i}" }.join(" ")
          scope.order(Arel.sql("CASE tickets.status #{order} END #{@direction}"), number: :desc)
        else
          scope.order(@sort => @direction, number: :desc)
        end
      end

      def load_form_data
        customer = @ticket.customer
        @categories = ::TicketCategory.active.ordered.to_a
        @categories |= [@ticket.ticket_category] if @ticket.ticket_category
        @invoices = customer ? ownership.invoices(customer.customer_invoices).order(invoice_date: :desc).limit(200) : []
        @credit_notes = customer ? ownership.credit_notes(customer_credit_notes(customer)).order(created_at: :desc).limit(200) : []
        @assignees = staff if ::Ticket.manager?(current_user) && @ticket.new_record?
      end

      def customer_credit_notes(customer)
        ::CreditNote.where(customer_id: customer.id).where.not(status: %w[draft void])
      end

      # The invoice and credit note must be the ticket's customer's and ones
      # this user can see; anything else is dropped (the model also checks
      # they belong to the customer).
      def restrict_links!
        customer = @ticket.customer
        return unless customer

        if @ticket.customer_invoice_id_changed? && @ticket.customer_invoice_id.present?
          @ticket.customer_invoice = ownership.invoices(customer.customer_invoices).find_by(id: @ticket.customer_invoice_id)
        end
        return unless @ticket.credit_note_id_changed? && @ticket.credit_note_id.present?

        @ticket.credit_note = ownership.credit_notes(customer_credit_notes(customer)).find_by(id: @ticket.credit_note_id)
      end

      def set_ticket
        @ticket = ownership.tickets(::Ticket.all).find(params[:id])
      end

      def visible_customers
        ownership.customers(::Customer.all)
      end

      def staff
        ::User.where(company_id: Current.company.id).active.order(:name)
      end

      def ownership
        @ownership ||= ::Sales::OwnershipScope.for(current_user)
      end

      def parse_date(key)
        params[key].presence&.to_date
      rescue ArgumentError, TypeError, Date::Error
        nil
      end

      def require_ticket_area
        return if ::Sales::OwnershipScope.applies_to?(Current.company)

        flash[:alert] = t("flash.feature_unavailable", default: "That feature isn't available for your business type.")
        redirect_to admin_root_path
      end

      def require_ticket_access
        return if ::Ticket.worker?(current_user)

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_root_path
      end

      def ticket_params
        params.require(:ticket).permit(:subject, :description, :ticket_category_id, :priority,
          :customer_invoice_id, :credit_note_id, images: [])
      end
    end
  end
end
