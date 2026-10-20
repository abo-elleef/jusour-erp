# frozen_string_literal: true

module Admin
  module Sales
    class CustomerStatementsController < BaseController
      before_action :set_customer, only: %i[show]

      # Server-side sort keys → SQL. Balances live on each customer's AR treasury
      # (a stored column), so the whole list sorts and pages in the database.
      SORTS = {
        "name" => "LOWER(customers.name)",
        "customer_type" => "customers.customer_type",
        "tier" => "LOWER(price_tiers.name)",
        "balance" => "COALESCE(treasuries.balance_cents, 0)",
        "last_invoice" => "last_invoices.last_invoice_date"
      }.freeze
      DEFAULT_SORT = "balance"

      def index
        @sort = SORTS.key?(params[:sort]) ? params[:sort] : DEFAULT_SORT
        @direction = params[:dir] == "asc" ? "asc" : "desc"
        @query = params[:query].to_s.strip

        # Anyone who was ever invoiced, of any type — plus anyone still carrying a
        # balance without an invoice (an opening balance), so no debt is hidden.
        listed = Customer.left_joins(:ar_treasury)
          .where(id: CustomerInvoice.select(:customer_id))
          .or(Customer.left_joins(:ar_treasury).where.not(treasuries: { balance_cents: 0 }))
        @total_ar_cents = listed.sum("COALESCE(treasuries.balance_cents, 0)")

        # Latest real sale per customer — drafts and voids aren't sales.
        last_invoices = CustomerInvoice.where.not(status: %w[draft void])
          .group(:customer_id).select("customer_id, MAX(invoice_date) AS last_invoice_date")
        scope = listed.left_joins(:price_tier).includes(:ar_treasury, :price_tier)
          .joins("LEFT JOIN (#{last_invoices.to_sql}) last_invoices ON last_invoices.customer_id = customers.id")
          .select("customers.*, last_invoices.last_invoice_date")
        if @query.present?
          term = "%#{Customer.sanitize_sql_like(@query)}%"
          scope = scope.where(
            "customers.name ILIKE :t OR customers.phone ILIKE :t OR customers.phone_secondary ILIKE :t " \
            "OR customers.legacy_code ILIKE :t", t: term
          )
        end
        order = Arel.sql("#{SORTS.fetch(@sort)} #{@direction.upcase} NULLS LAST, customers.id ASC")
        @pagy, @customers = pagy(:offset, scope.order(order), limit: 50)
      end

      def show
        @statement = ::Sales::CustomerAgingService.new(@customer).call
        @invoices = @customer.customer_invoices.recent.limit(50)
      end

      private

      def set_customer
        @customer = Customer.find(params[:id])
      end
    end
  end
end
