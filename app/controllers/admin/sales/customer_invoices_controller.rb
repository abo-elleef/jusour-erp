# frozen_string_literal: true

module Admin
  module Sales
    class CustomerInvoicesController < BaseController
      before_action :set_invoice, only: %i[show edit update confirm approve_payment reject_payment mark_dispatched complete_shipping void attach_payment_proof_image update_shipping_proof]
      before_action :require_own_invoice, except: %i[index new create]
      before_action :require_stage_visible, only: %i[show edit update update_shipping_proof]
      before_action :require_draft_for_edit, only: %i[edit update]
      before_action :require_payment_approver, only: %i[approve_payment reject_payment]
      before_action -> { require_sales_permission("sales:dispatch") }, only: :mark_dispatched
      before_action -> { require_sales_permission("sales:complete_shipping") }, only: :complete_shipping
      before_action :require_shipping_proof_permission, only: :update_shipping_proof

      def index
        @status = params[:status].presence_in(%w[draft pending_payment_confirmation confirmed historical void])
        @shipping = params[:shipping].presence_in(CustomerInvoice::SHIPPING_STATUSES)
        visible = ownership.invoices
        scope = visible.recent.includes(:customer, :location)
        scope = scope.where(status: @status) if @status
        scope = scope.where(shipping_status: @shipping) if @shipping
        @customer = ownership.customers.find_by(id: params[:customer_id]) if params[:customer_id].present?
        scope = scope.where(customer: @customer) if @customer
        @from_date = parse_filter_date(params[:from_date])
        @to_date = parse_filter_date(params[:to_date])
        scope = scope.where(invoice_date: @from_date..) if @from_date
        scope = scope.where(invoice_date: ..@to_date) if @to_date
        @tracking = params[:tracking].to_s.strip.presence
        if @tracking
          scope = scope.where("customer_invoices.shipping_tracking_number ILIKE ?",
            "%#{CustomerInvoice.sanitize_sql_like(@tracking)}%")
        end
        @customers = ownership.customers.order(:name)
        @pagy, @invoices = pagy(:offset, scope, limit: 50)
        @draft_count = visible.draft.count
        @pending_confirmation_count = visible.pending_payment_confirmation.count
        @waiting_for_shipping_count = visible.confirmed.waiting_for_shipping.count
        @outstanding_cents = visible.outstanding.sum(Arel.sql("total_cents - amount_paid_cents"))
        @filter_stages = filter_stages(visible)
      end

      def new
        @invoice = CustomerInvoice.new(invoice_date: Date.current, location_id: default_location&.id,
          customer_id: ownership.customers.find_by(id: params[:customer_id])&.id)
        @invoice.customer_invoice_lines.build
        load_form_data
      end

      def create
        @invoice = CustomerInvoice.new(invoice_params)
        @invoice.user = current_user
        @invoice.company ||= Current.company
        @invoice.status = "draft"

        if customer_allowed?(@invoice) && @invoice.save
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
        @invoice.assign_attributes(invoice_params)
        if customer_allowed?(@invoice) && @invoice.save
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
        redirect_after_change(@invoice, notice: t("sales.customer_invoices.flash.payment_rejected"))
      end

      # "dispatch" is reserved by ActionController::Metal (the core method that
      # invokes an action) — naming this action that would shadow it.
      #
      # The waybill photo and tracking number are optional here. They're
      # assigned before the service runs so its own update! saves them in the
      # same transaction: a bad image refuses the whole dispatch (nothing is
      # charged) instead of leaving a shipped invoice with a half-saved proof.
      def mark_dispatched
        @invoice.assign_attributes(shipping_proof_params)
        ::Sales::DispatchCustomerInvoiceService.new(@invoice, current_user).call
        redirect_after_change(@invoice, notice: t("sales.customer_invoices.flash.dispatched"))
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

      # The courier's system shows the order delivered. No money moves.
      def complete_shipping
        ::Sales::CompleteShippingService.new(@invoice, current_user).call
        redirect_after_change(@invoice, notice: t("sales.customer_invoices.flash.shipping_completed"))
      rescue ::Sales::CompleteShippingService::Error => e
        redirect_to admin_sales_customer_invoice_path(@invoice), alert: e.message
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

      # Adds or changes the waybill photo / tracking number after dispatch.
      # A blank tracking number clears it; a blank photo keeps the current one
      # (replace to change, no delete — same as the payment proof).
      def update_shipping_proof
        unless @invoice.delivery? && @invoice.shipping_proof_editable?
          redirect_to admin_sales_customer_invoice_path(@invoice),
            alert: t("sales.customer_invoices.flash.cannot_update_shipping_proof")
          return
        end

        attrs = shipping_proof_params
        attrs[:shipping_tracking_number] = params.dig(:customer_invoice, :shipping_tracking_number).to_s
        if @invoice.update(attrs)
          redirect_to admin_sales_customer_invoice_path(@invoice),
            notice: t("sales.customer_invoices.flash.shipping_proof_saved")
        else
          redirect_to admin_sales_customer_invoice_path(@invoice),
            alert: @invoice.errors.full_messages.to_sentence
        end
      end

      private

      # Only what was actually sent: a blank file field means "keep the photo".
      def shipping_proof_params
        raw = params.fetch(:customer_invoice, {}).permit(:shipping_tracking_number, :waybill_image)
        raw.to_h.symbolize_keys.select { |_key, value| value.present? }
      end

      def require_shipping_proof_permission
        return if current_user.can?("sales:dispatch") || current_user.can?("sales:complete_shipping")

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_sales_customer_invoice_path(@invoice)
      end

      # Stages the status/shipping filter chips and count cards are shown for:
      # every stage for the owner and unconfigured roles; otherwise the stages
      # the role may see (Sales::StageVisibility) plus any stage the user's own
      # always-visible invoices are in, so a chip never leads only to nothing.
      def filter_stages(visible)
        return CustomerInvoice::STAGES if ::Sales::StageVisibility.all_stages?(current_user)

        own = visible.distinct.pluck(:status, :shipping_status).map do |status, shipping|
          status == "confirmed" && shipping.present? ? shipping : status
        end
        ::Sales::StageVisibility.visible_stages(current_user) | own
      end

      def confirm_now
        result = ::Sales::ConfirmCustomerInvoiceService.new(@invoice || CustomerInvoice.find(params[:id]), current_user).call
        key = if result.pending_confirmation
                "submitted_for_confirmation"
              elsif result.credit_warning
                "confirmed_with_warning"
              else
                "confirmed"
              end
        redirect_after_change(result.invoice, notice: t("sales.customer_invoices.flash.#{key}"))
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

      # After an action moves an invoice to a stage this user's role can't see
      # (e.g. a wallet holder approves a payment and it goes on to shipping),
      # land them back on their list with the success message rather than on a
      # page that would refuse them.
      def redirect_after_change(invoice, notice:)
        if ownership.can_see_invoice?(invoice.reload)
          redirect_to admin_sales_customer_invoice_path(invoice), notice: notice
        elsif ::Sales::PaymentApproval.approver_anywhere?(current_user)
          redirect_to admin_sales_customer_invoices_path(status: "pending_payment_confirmation"), notice: notice
        else
          redirect_to admin_sales_customer_invoices_path, notice: notice
        end
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

      # The method's own approvers when it has any, else sales:confirm_payments
      # (Sales::PaymentApproval). The owner can always approve.
      # The owner's role × stage grid (Sales::StageVisibility) — your own
      # invoices and approvals you're responsible for always stay visible.
      def require_stage_visible
        return if ownership.can_see_invoice?(@invoice)

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_sales_customer_invoices_path
      end

      # Someone else's invoice (Sales::OwnershipScope) — answer as if it didn't
      # exist rather than say whose it is.
      def require_own_invoice
        raise ActiveRecord::RecordNotFound unless ownership.owns_invoice?(@invoice)
      end

      def ownership
        @ownership ||= ::Sales::OwnershipScope.for(current_user)
      end

      # A rep can't invoice another rep's customer. Checked only when the
      # customer is being set, so an old draft keeps saving.
      def customer_allowed?(invoice)
        return true unless invoice.new_record? || invoice.customer_id_changed?
        return true if invoice.customer_id.blank? || ownership.customers.exists?(id: invoice.customer_id)

        invoice.errors.add(:customer_id, t("sales.ownership.customer_not_yours"))
        false
      end

      def require_payment_approver
        return if ::Sales::PaymentApproval.can_approve?(current_user, @invoice)

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_sales_customer_invoice_path(@invoice)
      end

      def require_sales_permission(key)
        return if current_user.can?(key)

        flash[:alert] = t("flash.access_denied")
        redirect_to(@invoice ? admin_sales_customer_invoice_path(@invoice) : admin_sales_customer_invoices_path)
      end

      def load_form_data
        # Every customer, not just commercial ones: the distribution vertical sells
        # to walk-in doctors through this same form, settling at the counter. Credit
        # is still controlled where it matters — at confirm, against the limits.
        # A rep picks only their own customers; an existing draft keeps its own.
        customers = ownership.customers
        if @invoice&.persisted? && @invoice.customer_id_in_database
          customers = customers.or(Customer.where(id: @invoice.customer_id_in_database))
        end
        @customers = customers.order(:name)
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
          :delivery_fee_pounds, :standard_delivery_fee_pounds, :payment_proof_image,
          customer_invoice_lines_attributes: %i[id ingredient_id quantity unit unit_price_pounds _destroy]
        )
      end
    end
  end
end
