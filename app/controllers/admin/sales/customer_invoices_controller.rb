# frozen_string_literal: true

module Admin
  module Sales
    class CustomerInvoicesController < BaseController
      before_action :set_invoice, only: %i[show confirm record_payment]

      def index
        @status = params[:status].presence_in(%w[draft confirmed historical void])
        scope = CustomerInvoice.recent.includes(:customer, :location)
        scope = scope.where(status: @status) if @status
        @pagy, @invoices = pagy(:offset, scope, limit: 50)
        @draft_count = CustomerInvoice.draft.count
        @outstanding_cents = CustomerInvoice.outstanding.sum(Arel.sql("total_cents - amount_paid_cents"))
      end

      def new
        @invoice = CustomerInvoice.new(invoice_date: Date.current, location_id: default_location&.id,
          customer_id: params[:customer_id].presence)
        @invoice.customer_invoice_lines.build
        load_form_data
      end

      def create
        @invoice = CustomerInvoice.new(invoice_params)
        @invoice.user = current_user
        @invoice.company ||= Current.company
        @invoice.status = "draft"

        if @invoice.save
          if params[:commit_action] == "confirm"
            confirm_now
          else
            redirect_to admin_sales_customer_invoice_path(@invoice),
              notice: t("sales.customer_invoices.flash.saved")
          end
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def show
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def confirm
        confirm_now
      end

      def record_payment
        treasury = Treasury.active.payable.visible_to(current_user).find_by(id: params[:treasury_id])
        amount_cents = (params[:amount].to_f * 100).round

        ::Sales::RecordCustomerPaymentService.new(
          customer: @invoice.customer, treasury: treasury, amount_cents: amount_cents,
          user: current_user, payment_date: parse_date(params[:payment_date]) || Date.current,
          notes: params[:notes].presence
        ).call

        redirect_to admin_sales_customer_invoice_path(@invoice),
          notice: t("sales.customer_invoices.flash.payment_recorded")
      rescue ::Sales::RecordCustomerPaymentService::Error => e
        redirect_to admin_sales_customer_invoice_path(@invoice), alert: e.message
      end

      private

      def confirm_now
        result = ::Sales::ConfirmCustomerInvoiceService.new(@invoice || CustomerInvoice.find(params[:id]), current_user).call
        key = result.credit_warning ? "confirmed_with_warning" : "confirmed"
        redirect_to admin_sales_customer_invoice_path(result.invoice),
          notice: t("sales.customer_invoices.flash.#{key}")
      rescue ::Sales::ConfirmCustomerInvoiceService::CreditBlocked => e
        redirect_to admin_sales_customer_invoice_path(@invoice || CustomerInvoice.find(params[:id])), alert: e.message
      rescue ::Sales::ConfirmCustomerInvoiceService::Error => e
        redirect_to admin_sales_customer_invoice_path(@invoice || CustomerInvoice.find(params[:id])), alert: e.message
      # Anything else (e.g. a ledger/journal failure) would otherwise 500 and look
      # like "nothing happened" — the invoice silently stays a draft. Surface it.
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("[ConfirmCustomerInvoice] #{e.class}: #{e.message}")
        redirect_to admin_sales_customer_invoice_path(@invoice || CustomerInvoice.find(params[:id])),
          alert: t("sales.customer_invoices.flash.confirm_failed", error: e.message)
      end

      def set_invoice
        @invoice = CustomerInvoice.find(params[:id])
      end

      def load_form_data
        # Every customer, not just commercial ones: the distribution vertical sells
        # to walk-in doctors through this same form, settling at the counter. Credit
        # is still controlled where it matters — at confirm, against the limits.
        @customers = Customer.order(:name)
        @settlement_methods = ::Sales::SettlementTreasury.available_methods(user: current_user)
        @locations = Location.active.ordered
        @ingredients = Ingredient.active.order(:name)
        # Teammates the sale can be credited to (drives their bonus).
        @salespeople = User.where(company_id: Current.company.id).active.order(:name)
      end

      def default_location
        Location.active.ordered.first
      end

      def parse_date(raw)
        return if raw.blank?

        Date.parse(raw.to_s)
      rescue ArgumentError
        nil
      end

      def invoice_params
        params.require(:customer_invoice).permit(
          :customer_id, :location_id, :invoice_date, :notes, :salesperson_id, :payment_method,
          customer_invoice_lines_attributes: %i[id ingredient_id quantity unit unit_price_pounds _destroy]
        )
      end
    end
  end
end
