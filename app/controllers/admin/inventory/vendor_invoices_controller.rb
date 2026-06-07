# frozen_string_literal: true

module Admin
  module Inventory
    class VendorInvoicesController < BaseController
      before_action :set_vendor_invoice, only: %i[show record_payment void]

      def index
        authorize_inventory_index!(VendorInvoice)
        @q = VendorInvoice.ransack(params[:q])
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @vendor_invoices = @q.result.includes(:supplier, :user).recent.limit(200)
        scope = VendorInvoice.all
        @total_count = scope.count
        @unpaid_count = scope.unpaid.count
        @partially_paid_count = scope.partially_paid.count
        @paid_count = scope.paid.count
        @outstanding_total_cents = scope.outstanding.sum(Arel.sql("total_cents - amount_paid_cents"))
        @suppliers = Supplier.active.order(:name)
      end

      def show
        authorize_inventory!(:show)
        @lines = @vendor_invoice.vendor_invoice_lines.includes(:ingredient, :stock_batch)
        @payments = @vendor_invoice.vendor_invoice_payments.includes(:user, :treasury).order(payment_date: :desc, created_at: :desc)
        @treasuries = Treasury.active.payable.ordered
      end

      def new
        @vendor_invoice = VendorInvoice.new(
          user: current_user,
          invoice_date: Date.current,
          received_on: Date.current
        )
        authorize_inventory!(:create)
        prefill_supplier if params[:supplier_id].present?
        build_line_items
        load_form_data
      end

      def create
        @vendor_invoice = VendorInvoice.new(vendor_invoice_params.merge(user: current_user))
        authorize_inventory!(:create)

        if @vendor_invoice.vendor_invoice_lines.reject(&:marked_for_destruction?).any? { |l| l.ingredient_id.present? }
          ::Inventory::ReceiveVendorInvoiceService.new(@vendor_invoice, current_user).call
          redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice),
            notice: t("flash.vendor_invoice.created")
        else
          @vendor_invoice.errors.add(:base, t("inventory.vendor_invoices.errors.lines_required"))
          build_line_items
          load_form_data
          render :new, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordInvalid
        build_line_items
        load_form_data
        render :new, status: :unprocessable_entity
      end

      def record_payment
        authorize_inventory!(:record_vendor_invoice_payment)
        treasury = Treasury.find(params[:treasury_id])
        payment_date = params[:payment_date].present? ? Date.parse(params[:payment_date]) : Date.current
        amount_cents = (BigDecimal(params[:payment_amount_dollars].to_s.presence || "0") * 100).round

        ::Accounting::RecordVendorInvoicePaymentService.new(
          vendor_invoice: @vendor_invoice,
          user: current_user,
          treasury: treasury,
          amount_cents: amount_cents,
          payment_date: payment_date
        ).call

        notice_key = @vendor_invoice.reload.paid? ? "flash.vendor_invoice.paid" : "flash.vendor_invoice.payment_recorded"
        redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice), notice: t(notice_key)
      rescue Accounting::RecordVendorInvoicePaymentService::Error,
             ActiveRecord::RecordInvalid => e
        @lines = @vendor_invoice.vendor_invoice_lines.includes(:ingredient, :stock_batch)
        @payments = @vendor_invoice.vendor_invoice_payments.includes(:user, :treasury).order(payment_date: :desc, created_at: :desc)
        @treasuries = Treasury.active.payable.ordered
        flash.now[:alert] = e.message
        render :show, status: :unprocessable_entity
      end

      def void
        authorize_inventory!(:destroy)
        unless @vendor_invoice.amount_paid_cents.zero?
          redirect_to admin_inventory_vendor_invoice_path(@vendor_invoice),
            alert: t("flash.vendor_invoice.cannot_void")
          return
        end

        ActiveRecord::Base.transaction do
          @vendor_invoice.update!(payment_status: "void")
          Accounting::SupplierApLedgerService.reverse_invoice!(
            invoice: @vendor_invoice,
            user: current_user
          )
        end
        redirect_to admin_inventory_vendor_invoices_path, notice: t("flash.vendor_invoice.voided")
      end

      private

      def set_vendor_invoice
        @vendor_invoice = VendorInvoice.find(params[:id])
      end

      def prefill_supplier
        @vendor_invoice.supplier = Supplier.find_by(id: params[:supplier_id])
      end

      def build_line_items
        remaining = 5 - @vendor_invoice.vendor_invoice_lines.reject(&:marked_for_destruction?).size
        remaining.times { @vendor_invoice.vendor_invoice_lines.build } if remaining.positive?
      end

      def load_form_data
        @suppliers = Supplier.active.order(:name)
        @ingredients = Ingredient.active.order(:name)
      end

      def vendor_invoice_params
        permitted = params.require(:vendor_invoice).permit(
          :supplier_id, :invoice_number, :invoice_date, :received_on, :notes,
          vendor_invoice_lines_attributes: %i[
            id ingredient_id quantity unit_price_dollars expires_on batch_reference line_notes _destroy
          ]
        )
        permitted[:vendor_invoice_lines_attributes]&.each_value do |attrs|
          dollars = attrs.delete(:unit_price_dollars)
          attrs[:unit_price_cents] = (BigDecimal(dollars.to_s.presence || "0") * 100).round
        end
        permitted
      end
    end
  end
end
