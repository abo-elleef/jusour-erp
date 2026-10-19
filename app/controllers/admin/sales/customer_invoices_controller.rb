# frozen_string_literal: true

module Admin
  module Sales
    class CustomerInvoicesController < BaseController
      before_action :set_invoice, only: %i[show edit update confirm approve_payment reject_payment mark_dispatched void attach_payment_proof_image]
      before_action :require_draft_for_edit, only: %i[edit update]
      before_action :require_confirm_payments_access, only: %i[approve_payment reject_payment]

      def index
        @status = params[:status].presence_in(%w[draft pending_payment_confirmation confirmed historical void])
        scope = CustomerInvoice.recent.includes(:customer, :location)
        scope = scope.where(status: @status) if @status
        @customer = Customer.find_by(id: params[:customer_id]) if params[:customer_id].present?
        scope = scope.where(customer: @customer) if @customer
        @from_date = parse_filter_date(params[:from_date])
        @to_date = parse_filter_date(params[:to_date])
        scope = scope.where(invoice_date: @from_date..) if @from_date
        scope = scope.where(invoice_date: ..@to_date) if @to_date
        @customers = Customer.order(:name)
        @pagy, @invoices = pagy(:offset, scope, limit: 50)
        @draft_count = CustomerInvoice.draft.count
        @pending_confirmation_count = CustomerInvoice.pending_payment_confirmation.count
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

      # A draft hasn't posted anything yet (no stock deducted, no AR/treasury
      # entry) — nothing to reverse, so it's the only state this edits in
      # place. A confirmed invoice is a settled document, same reasoning as
      # Voucher/CreditNote: move it through states, don't rewrite it.
      def edit
        load_form_data
      end

      def update
        if @invoice.update(invoice_params)
          if params[:commit_action] == "confirm"
            confirm_now
          else
            redirect_to admin_sales_customer_invoice_path(@invoice),
              notice: t("sales.customer_invoices.flash.saved")
          end
        else
          load_form_data
          render :edit, status: :unprocessable_entity
        end
      end

      def show; end

      def confirm
        confirm_now
      end

      # Approving a pending online payment re-enters ConfirmCustomerInvoiceService —
      # the invoice is no longer draft, so it falls straight through to settle_now!.
      def approve_payment
        confirm_now
      end

      def reject_payment
        unless @invoice.pending_payment_confirmation?
          redirect_to admin_sales_customer_invoice_path(@invoice), alert: t("sales.customer_invoices.errors.not_pending")
          return
        end

        @invoice.update!(status: "draft")
        redirect_to admin_sales_customer_invoice_path(@invoice),
          notice: t("sales.customer_invoices.flash.payment_rejected")
      end

      # "dispatch" is reserved by ActionController::Metal (the core method that
      # invokes an action) — naming this action that would shadow it.
      def mark_dispatched
        ::Sales::DispatchCustomerInvoiceService.new(@invoice, current_user).call
        redirect_to admin_sales_customer_invoice_path(@invoice),
          notice: t("sales.customer_invoices.flash.dispatched")
      rescue ::Sales::DispatchCustomerInvoiceService::Error => e
        redirect_to admin_sales_customer_invoice_path(@invoice), alert: e.message
      # Anything else (e.g. a ledger/journal failure) would otherwise 422 and look
      # like nothing happened — the invoice silently stays undispatched. Surface it,
      # same as confirm_now does.
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("[DispatchCustomerInvoice] #{e.class}: #{e.message}")
        redirect_to admin_sales_customer_invoice_path(@invoice),
          alert: t("sales.customer_invoices.flash.dispatch_failed", error: e.message)
      end

      # A draft (including one bounced back here by reject_payment) or a still-
      # pending invoice posts nothing yet, so voiding it is just marking it
      # dead — same reasoning as Sales::CreditNotesController#void.
      def void
        unless @invoice.voidable?
          redirect_to admin_sales_customer_invoice_path(@invoice), alert: t("sales.customer_invoices.errors.cannot_void")
          return
        end

        @invoice.update!(status: "void")
        redirect_to admin_sales_customer_invoices_path, notice: t("sales.customer_invoices.flash.voided")
      end

      # Mirrors Admin::Inventory::VendorInvoicesController#attach_invoice_image:
      # one attachment, replace to change, no delete route.
      def attach_payment_proof_image
        if @invoice.void?
          redirect_to admin_sales_customer_invoice_path(@invoice),
            alert: t("sales.customer_invoices.flash.cannot_attach_payment_proof")
          return
        end

        image = params.dig(:customer_invoice, :payment_proof_image)
        if image.blank?
          redirect_to admin_sales_customer_invoice_path(@invoice),
            alert: t("sales.customer_invoices.flash.payment_proof_required")
          return
        end

        @invoice.payment_proof_image.attach(image)
        redirect_to admin_sales_customer_invoice_path(@invoice),
          notice: t("sales.customer_invoices.flash.payment_proof_attached")
      end

      private

      def confirm_now
        result = ::Sales::ConfirmCustomerInvoiceService.new(@invoice || CustomerInvoice.find(params[:id]), current_user).call
        key = if result.pending_confirmation
                "submitted_for_confirmation"
              elsif result.credit_warning
                "confirmed_with_warning"
              else
                "confirmed"
              end
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

      def parse_filter_date(value)
        Date.iso8601(value) if value.present?
      rescue Date::Error
        nil
      end

      def require_draft_for_edit
        return if @invoice.draft?

        redirect_to admin_sales_customer_invoice_path(@invoice), alert: t("sales.customer_invoices.errors.not_draft_for_edit")
      end

      def require_confirm_payments_access
        return if current_user.can?("sales:confirm_payments")

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_sales_customer_invoices_path
      end

      def load_form_data
        # Every customer, not just commercial ones: the distribution vertical sells
        # to walk-in doctors through this same form, settling at the counter. Credit
        # is still controlled where it matters — at confirm, against the limits.
        @customers = Customer.order(:name)
        @locations = Location.active.ordered
        @ingredients = Ingredient.active.order(:name)
        @shipping_companies = ShippingCompany.active.ordered
        @sales_payment_methods = ::Sales::PaymentMethod.active.ordered
        # Teammates the sale can be credited to (drives their bonus).
        @salespeople = User.where(company_id: Current.company.id).active.order(:name)
      end

      def default_location
        Location.active.ordered.first
      end

      def invoice_params
        params.require(:customer_invoice).permit(
          :customer_id, :location_id, :invoice_date, :notes, :salesperson_id, :payment_method,
          :fulfillment_method, :shipping_company_id, :sales_payment_method_id,
          :delivery_fee_pounds, :standard_delivery_fee_pounds,
          customer_invoice_lines_attributes: %i[id ingredient_id quantity unit unit_price_pounds _destroy]
        )
      end
    end
  end
end
