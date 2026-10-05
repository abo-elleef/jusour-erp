# frozen_string_literal: true

module Accounting
  # Fired when editing a vendor invoice leaves the supplier's AP balance
  # negative — i.e. the supplier has been overpaid. See
  # Inventory::UpdateVendorInvoiceService#notify_if_balance_turned_negative!.
  class NotifyVendorBalanceNegativeJob < ApplicationJob
    queue_as :default

    def perform(supplier_id, invoice_id, balance_cents)
      supplier = Supplier.find_by(id: supplier_id)
      return unless supplier

      with_company(supplier.company) do
        invoice = VendorInvoice.find_by(id: invoice_id)

        Accounting::NotifyService.deliver_to_managers(
          message_key: "vendor_balance_negative",
          message_params: {
            supplier: supplier.name,
            supplier_id: supplier.id,
            balance_cents: balance_cents.to_i,
            invoice_number: invoice&.invoice_number,
            vendor_invoice_id: invoice&.id
          }
        )
      end
    end
  end
end
