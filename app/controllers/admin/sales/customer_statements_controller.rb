# frozen_string_literal: true

module Admin
  module Sales
    class CustomerStatementsController < BaseController
      before_action :set_customer, only: %i[show]

      def index
        @customers = Customer.where(customer_type: "commercial").order(:name).to_a
        # AR balance per customer (reads each ledger treasury).
        @balances = @customers.index_with(&:ar_balance_cents)
        @total_ar_cents = @balances.values.sum
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
