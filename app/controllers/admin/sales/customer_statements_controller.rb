# frozen_string_literal: true

module Admin
  module Sales
    class CustomerStatementsController < BaseController
      before_action :set_customer, only: %i[show record_payment]

      def index
        @customers = Customer.where(customer_type: "commercial").order(:name).to_a
        # AR balance per customer (reads each ledger treasury).
        @balances = @customers.index_with(&:ar_balance_cents)
        @total_ar_cents = @balances.values.sum
      end

      def show
        @statement = ::Sales::CustomerAgingService.new(@customer).call
        @invoices = @customer.customer_invoices.recent.limit(50)
        @payments = @customer.customer_payments.recent.limit(20)
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def record_payment
        treasury = Treasury.active.payable.visible_to(current_user).find_by(id: params[:treasury_id])
        amount_cents = (params[:amount].to_f * 100).round

        ::Sales::RecordCustomerPaymentService.new(
          customer: @customer, treasury: treasury, amount_cents: amount_cents,
          user: current_user, payment_date: parse_date(params[:payment_date]) || Date.current,
          notes: params[:notes].presence
        ).call

        redirect_to admin_sales_customer_statement_path(@customer),
          notice: t("sales.customer_invoices.flash.payment_recorded")
      rescue ::Sales::RecordCustomerPaymentService::Error => e
        redirect_to admin_sales_customer_statement_path(@customer), alert: e.message
      end

      private

      def set_customer
        @customer = Customer.find(params[:id])
      end

      def parse_date(raw)
        return if raw.blank?

        Date.parse(raw.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
