# frozen_string_literal: true

require "csv"

module Admin
  class CustomersController < BaseController
    TAB_FRAME = "customer_tab"

    before_action :set_customer, only: %i[show edit update destroy block unblock]

    def index
      authorize Customer

      # A sales rep without sales:see_all lists their own customers only
      # (Sales::OwnershipScope); restaurants are never narrowed.
      visible = ownership.customers
      @q = visible.ransack(params[:q])
      @sort = parse_index_sort_param
      @direction = parse_index_sort_direction_param
      @joined_from = parse_date_param(:joined_from)
      @joined_to = parse_date_param(:joined_to)
      scope = joined_scope(@q.result)
      scope = filter_by_salesperson(scope)

      if request.format.csv?
        return send_data customers_csv(scope.order(@sort => @direction, id: :asc)),
                         filename: "customers-#{Date.current.iso8601}.csv",
                         type: "text/csv; charset=utf-8"
      end

      @total_count = visible.count
      @loyalty_members_count = visible.where("loyalty_points > 0").count
      @total_lifetime_spend_cents = visible.sum(:total_spent_cents)
      @date_filtered = @joined_from.present? || @joined_to.present?
      # With a joined-date range the card counts that period instead of this month.
      @new_in_period_count =
        if @date_filtered
          joined_scope(visible).count
        else
          visible.where(created_at: Time.current.all_month).count
        end
      @filtered = @date_filtered || @salesperson_filter.present? ||
        (params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?))
      @show_salesperson = ::Sales::OwnershipScope.applies_to?(Current.company)
      @salespeople = salespeople if ownership.manages_assignment?
      @pagy, @customers = pagy(
        :offset,
        (@show_salesperson ? scope.includes(:assigned_user) : scope).order(@sort => @direction, id: :asc),
        limit: 25
      )
    end

    # Shell (header, stat cards) + one Turbo frame that lazy-loads the active
    # tab from this same URL (?tab=), like the supplier and staff pages: a
    # customer we keep selling to and following up with collects long lists.
    def show
      authorize @customer
      @tabs = visible_tabs
      @tab = @tabs.include?(params[:tab]) ? params[:tab] : @tabs.first

      if turbo_frame_request_id == TAB_FRAME
        send(:"load_#{@tab}_tab")
        # The admin layout is set explicitly and would override turbo-rails'
        # bare frame layout.
        render "tab", layout: "turbo_rails/frame"
      end
    end

    def new
      @customer = Customer.new
      @customer.addresses.build
      @salespeople = salespeople if ownership.manages_assignment?
      authorize @customer
    end

    def create
      @customer = Customer.new(customer_params)
      # A limited rep's new customer is theirs, so it doesn't vanish on save.
      @customer.assigned_user = current_user if ownership.limited?
      authorize @customer
      if @customer.save
        redirect_to admin_customer_path(@customer), notice: t("flash.customer.created")
      else
        @salespeople = salespeople if ownership.manages_assignment?
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @customer
      @customer.addresses.build if @customer.addresses.empty?
      @salespeople = salespeople if ownership.manages_assignment?
    end

    def update
      authorize @customer
      if @customer.update(customer_params)
        redirect_to admin_customer_path(@customer), notice: t("flash.customer.updated")
      else
        @salespeople = salespeople if ownership.manages_assignment?
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @customer
      if @customer.orders.exists?
        redirect_to admin_customer_path(@customer),
                    alert: t("flash.customer.cannot_delete_with_orders")
        return
      end

      @customer.destroy
      redirect_to admin_customers_path, notice: t("flash.customer.removed")
    end

    # Managers hand a page of customers to one salesperson (or back to nobody).
    def bulk_assign
      authorize Customer, :update?
      unless ownership.manages_assignment?
        redirect_to admin_customers_path, alert: t("flash.access_denied")
        return
      end

      ids = Array(params[:customer_ids]).compact_blank
      target = params[:assigned_user_id].to_s
      user = salespeople.find_by(id: target) unless target == "none"
      if ids.empty? || (target != "none" && user.nil?)
        redirect_back fallback_location: admin_customers_path, alert: t("customers.bulk_assign.nothing_selected")
        return
      end

      count = 0
      Customer.where(id: ids).find_each { |customer| count += 1 if customer.update(assigned_user: user) }
      redirect_back fallback_location: admin_customers_path,
        notice: t("customers.bulk_assign.done", count: count, name: user&.name || t("customers.salesperson.none"))
    end

    # Blocks the customer from placing self-orders on the public menu.
    def block
      authorize @customer
      reason = params[:blocked_reason].to_s.strip
      if reason.blank?
        redirect_to admin_customer_path(@customer), alert: t("flash.customer.block_reason_required")
        return
      end

      @customer.block!(by: current_user, reason: reason)
      redirect_to admin_customer_path(@customer), notice: t("flash.customer.blocked")
    end

    def unblock
      authorize @customer
      @customer.unblock!
      redirect_to admin_customer_path(@customer), notice: t("flash.customer.unblocked")
    end

    private

    TAB_PAGE_SIZE = 25

    # Which tabs this customer page has. Activity and the lead's history exist
    # only where the distribution sales area does (Sales::OwnershipScope); a
    # sales customer shows Orders/Loyalty only once it has any.
    def visible_tabs
      sales = ::Sales::OwnershipScope.applies_to?(Current.company)
      @sales_area = sales
      @tab_counts = {}
      tabs = ["overview"]
      if sales
        tabs << "activity"
        @tab_counts["activity"] = @customer.customer_activities.count
        if @customer.originating_lead_id
          tabs << "lead_history"
          @tab_counts["lead_history"] = ::LeadActivity.where(lead_id: @customer.originating_lead_id).count
        end
      end
      if invoices_visible?
        tabs << "invoices"
        @tab_counts["invoices"] = @customer.customer_invoices.count
      end
      tabs << "orders" if !sales || @customer.orders.exists?
      tabs << "loyalty" if !sales || @customer.loyalty_transactions.exists?
      tabs
    end

    def invoices_visible?
      current_user.can?("customers:manage") && Current.company&.feature_enabled?(:ar_credit_sales)
    end

    # The customer's details: block status, online-order summary, numbers,
    # the lead it came from, addresses. The lists live in their own tabs.
    def load_overview_tab
      @online_request_counts = OnlineOrderRequest.where(customer: @customer).group(:status).count
      load_origin if @sales_area
    end

    # Bazzar slice F: the customer's own timeline since it became a customer.
    def load_activity_tab
      @activity = ::CustomerActivity.new(customer: @customer)
      @can_log_activity = current_user.can?(::Admin::Customers::CustomerActivitiesController::PERMISSION)
      @activities_pagy, @activities = pagy(:offset, @customer.customer_activities.includes(:user).recent,
        limit: TAB_PAGE_SIZE)
    end

    # The lead it came from and that lead's timeline, read-only.
    def load_lead_history_tab
      @lead_activities_pagy, @lead_activities = pagy(:offset,
        ::LeadActivity.where(lead_id: @customer.originating_lead_id).includes(:user).recent,
        limit: TAB_PAGE_SIZE)
    end

    def load_invoices_tab
      @invoices_pagy, @invoices = pagy(:offset,
        @customer.customer_invoices.includes(:location).order(invoice_date: :desc, created_at: :desc),
        limit: TAB_PAGE_SIZE)
    end

    def load_orders_tab
      @orders_pagy, @orders = pagy(:offset, @customer.orders.order(created_at: :desc), limit: TAB_PAGE_SIZE)
    end

    def load_loyalty_tab
      @loyalty_pagy, @loyalty_transactions = pagy(:offset, @customer.loyalty_transactions.order(created_at: :desc),
        limit: TAB_PAGE_SIZE)
    end

    def load_origin
      @lead = @customer.originating_lead
      return unless @lead

      @lead_linkable = Current.company.feature_enabled?(:leads) && current_user.can?("leads:view") &&
        ownership.can_see_lead?(@lead)
    end

    # Someone else's customer is a 404 for a limited rep (Sales::OwnershipScope).
    def set_customer
      @customer = ownership.customers(Customer.includes(:addresses)).find(params[:id])
    end

    def ownership
      @ownership ||= ::Sales::OwnershipScope.for(current_user)
    end

    def salespeople
      User.where(company_id: Current.company.id).active.order(:name)
    end

    # "Salesperson" filter: one person, or "none" for the unassigned ones a
    # manager still has to hand out.
    def filter_by_salesperson(scope)
      return scope unless ownership.manages_assignment?

      @salesperson_filter = params[:assigned_user_id].presence
      case @salesperson_filter
      when nil then scope
      when "none" then scope.where(assigned_user_id: nil)
      else scope.where(assigned_user_id: @salesperson_filter)
      end
    end

    def parse_date_param(key)
      params[key].presence&.to_date
    rescue ArgumentError, TypeError, Date::Error
      nil
    end

    # Joined-date range is inclusive of both days, in the app time zone.
    def joined_scope(scope)
      scope = scope.where(created_at: @joined_from.beginning_of_day..) if @joined_from
      scope = scope.where(created_at: ..@joined_to.end_of_day) if @joined_to
      scope
    end

    def customers_csv(scope)
      credit = Current.company&.feature_enabled?(:ar_credit_sales)
      CSV.generate do |csv|
        header = [
          t("customers.csv.legacy_code"), t("customers.form.name"), t("customers.form.email"),
          t("customers.form.phone"), t("customers.form.phone_secondary"),
          t("customers.csv.default_address"), t("customers.table.loyalty"),
          t("customers.table.lifetime_spend"), t("customers.table.joined")
        ]
        header += [t("customers.form.customer_type"), t("customers.csv.ar_balance")] if credit
        csv << header

        # `each`, not `find_each`: find_each would drop the user's chosen sort order.
        scope.includes(*[:addresses, (:ar_treasury if credit)].compact).each do |customer|
          default_address = customer.addresses.find(&:is_default?) || customer.addresses.first
          row = [
            customer.legacy_code, customer.name, customer.email, customer.phone, customer.phone_secondary,
            default_address&.address, customer.loyalty_points,
            helpers.format_amount(customer.total_spent_cents), customer.created_at.to_date
          ]
          if credit
            row += [t("customers.form.types.#{customer.customer_type}"),
                    helpers.format_amount(customer.ar_balance_cents)]
          end
          csv << row
        end
      end
    end

    def parse_index_sort_param
      sort = params[:sort].to_s
      Customer::INDEX_SORTABLE_COLUMNS.include?(sort) ? sort : Customer::INDEX_DEFAULT_SORT
    end

    def parse_index_sort_direction_param
      params[:dir].to_s == "asc" ? "asc" : Customer::INDEX_DEFAULT_SORT_DIRECTION
    end

    def customer_params
      permitted = %i[name email phone phone_secondary standing_note]
      permitted << :assigned_user_id if ownership.manages_assignment?
      # Commercial / credit fields only when the company runs credit sales.
      if Current.company&.feature_enabled?(:ar_credit_sales)
        permitted += %i[customer_type price_tier_id discount_override_percent
                        credit_warning_limit_pounds credit_hard_limit_pounds credit_terms_days]
      end
      params.require(:customer).permit(
        *permitted,
        addresses_attributes: %i[id label address is_default position _destroy]
      )
    end
  end
end
