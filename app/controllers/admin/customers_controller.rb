# frozen_string_literal: true

require "csv"

module Admin
  class CustomersController < BaseController
    before_action :set_customer, only: %i[show edit update destroy]

    def index
      authorize Customer

      @q = Customer.ransack(params[:q])
      @sort = parse_index_sort_param
      @direction = parse_index_sort_direction_param
      @joined_from = parse_date_param(:joined_from)
      @joined_to = parse_date_param(:joined_to)
      scope = joined_scope(@q.result)

      if request.format.csv?
        return send_data customers_csv(scope.order(@sort => @direction, id: :asc)),
                         filename: "customers-#{Date.current.iso8601}.csv",
                         type: "text/csv; charset=utf-8"
      end

      @total_count = Customer.count
      @loyalty_members_count = Customer.where("loyalty_points > 0").count
      @total_lifetime_spend_cents = Customer.sum(:total_spent_cents)
      @date_filtered = @joined_from.present? || @joined_to.present?
      # With a joined-date range the card counts that period instead of this month.
      @new_in_period_count =
        if @date_filtered
          joined_scope(Customer.all).count
        else
          Customer.where(created_at: Time.current.all_month).count
        end
      @filtered = @date_filtered || (params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?))
      @pagy, @customers = pagy(
        :offset,
        scope.order(@sort => @direction, id: :asc),
        limit: 25
      )
    end

    def show
      authorize @customer
      @orders = @customer.orders.order(created_at: :desc).limit(50)
      if current_user.can?("customers:manage") && Current.company&.feature_enabled?(:ar_credit_sales)
        invoices = @customer.customer_invoices
        @invoices_count = invoices.count
        @invoices = invoices.includes(:location).order(invoice_date: :desc, created_at: :desc).limit(20)
      end
      @loyalty_transactions = @customer.loyalty_transactions.order(created_at: :desc).limit(20)
    end

    def new
      @customer = Customer.new
      @customer.addresses.build
      authorize @customer
    end

    def create
      @customer = Customer.new(customer_params)
      authorize @customer
      if @customer.save
        redirect_to admin_customer_path(@customer), notice: t("flash.customer.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @customer
      @customer.addresses.build if @customer.addresses.empty?
    end

    def update
      authorize @customer
      if @customer.update(customer_params)
        redirect_to admin_customer_path(@customer), notice: t("flash.customer.updated")
      else
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

    private

    def set_customer
      @customer = Customer.includes(:addresses).find(params[:id])
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
