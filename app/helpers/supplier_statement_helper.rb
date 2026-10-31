# frozen_string_literal: true

# A supplier statement row points back at whatever moved the AP balance: an
# invoice, a credit note, a voucher, a legacy invoice payment, or a manual
# journal entry. Each names itself and lives somewhere different, so the
# statement asks here rather than assuming.
module SupplierStatementHelper
  def supplier_statement_reference(source)
    case source
    when VendorInvoice        then [source.invoice_number, admin_inventory_vendor_invoice_path(source)]
    when VendorCreditNote     then [source.credit_note_number, admin_inventory_vendor_credit_note_path(source)]
    when Voucher              then [source.number, admin_accounting_voucher_path(source)]
    when VendorInvoicePayment then [source.vendor_invoice.invoice_number, admin_inventory_vendor_invoice_path(source.vendor_invoice)]
    when JournalEntry         then [source.entry_number, admin_accounting_journal_entry_path(source)]
    end
  end

  def supplier_statement_kind_label(kind)
    t("inventory.suppliers.statement.kinds.#{kind}", default: kind.to_s.humanize)
  end
end
