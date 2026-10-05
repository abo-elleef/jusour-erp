# frozen_string_literal: true

module Inventory
  class UpdateVendorInvoiceService
    class Error < StandardError; end

    def initialize(vendor_invoice, user, attributes, freight_amount_cents: 0, freight_treasury: nil)
      @invoice = vendor_invoice
      @user = user
      @attributes = attributes
      @freight_amount_cents = freight_amount_cents
      @freight_treasury = freight_treasury
      @stock_handler = VendorInvoiceStockHandler.new(@invoice, @user)
    end

    def call
      raise Error, I18n.t("inventory.vendor_invoices.errors.not_editable") unless @invoice.editable?

      old_ap_balance_cents = current_ap_balance_cents

      ActiveRecord::Base.transaction do
        lines_to_reverse = @invoice.vendor_invoice_lines.includes(:stock_batch, :ingredient).to_a

        lines_to_reverse.each { |line| @stock_handler.reverse_line(line) }
        Accounting::SupplierApLedgerService.reverse_invoice!(invoice: @invoice, user: @user)

        @invoice.assign_attributes(@attributes)
        @invoice.save!

        @invoice.vendor_invoice_lines.each { |line| @stock_handler.receive_line(line) }
        @invoice.reload
        Accounting::SupplierApLedgerService.record_invoice!(invoice: @invoice, user: @user)
        Accounting::SyncVendorInvoiceFreightService.call(
          invoice: @invoice,
          user: @user,
          amount_cents: @freight_amount_cents,
          treasury: @freight_treasury
        )

        # Cash already paid (amount_paid_cents) is untouched by the reverse/record
        # above — only the ap_invoice leg moves to the new total. So if the
        # corrected total lands below what was already paid, the AP treasury and
        # this invoice's own balance_due_cents both land on the right negative
        # number on their own; sync_payment_status! just has to catch up to it
        # (e.g. a "paid" invoice becoming "partially_paid" when the total rises).
        @invoice.sync_payment_status!
      end

      # Checked after the transaction commits, so a rolled-back edit never
      # fires a false alert. Only the crossing (was >= 0, now negative) notifies
      # — once the supplier is already in credit, further edits don't re-alert.
      notify_if_balance_turned_negative!(old_ap_balance_cents)

      @invoice
    end

    private

    def current_ap_balance_cents
      @invoice.supplier.reload.ap_balance_cents
    end

    def notify_if_balance_turned_negative!(old_balance_cents)
      return unless old_balance_cents >= 0

      new_balance_cents = current_ap_balance_cents
      return unless new_balance_cents.negative?

      Accounting::NotifyVendorBalanceNegativeJob.perform_later(
        @invoice.supplier_id, @invoice.id, new_balance_cents
      )
    end
  end
end
