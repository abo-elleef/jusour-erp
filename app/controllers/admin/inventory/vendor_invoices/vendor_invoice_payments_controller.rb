# frozen_string_literal: true

module Admin
  module Inventory
    module VendorInvoices
      class VendorInvoicePaymentsController < Admin::Inventory::BaseController
        before_action :set_invoice
        before_action :set_payment

        def destroy
          authorize_inventory!(:reverse_vendor_invoice_payment)

          ::Accounting::ReverseVendorInvoicePaymentService.new(payment: @payment, user: current_user).call

          redirect_to admin_inventory_vendor_invoice_path(@invoice),
            notice: t("flash.vendor_invoice.payment_reversed")
        rescue ::Accounting::ReverseVendorInvoicePaymentService::Error => e
          redirect_to admin_inventory_vendor_invoice_path(@invoice), alert: e.message
        end

        private

        def set_invoice
          @invoice = VendorInvoice.find(params[:vendor_invoice_id])
        end

        def set_payment
          @payment = @invoice.payment_vouchers.find(params[:id])
        end
      end
    end
  end
end
