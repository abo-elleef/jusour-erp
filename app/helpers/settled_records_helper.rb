# frozen_string_literal: true

# A voucher settles a document — an expense, an income, a supplier or customer
# invoice — or a party, when money moves on account. Each names itself
# differently and lives under a different part of the app, so anything
# displaying what a voucher settled has to ask rather than assume.
#
# This existed implicitly while only expenses and incomes could be settled:
# both answer `description`, both live under admin/accounting, and the views
# called those directly. The moment a voucher could pay an invoice that broke —
# a VendorInvoice has an invoice_number, not a description, and lives under
# admin/inventory.
module SettledRecordsHelper
  def settled_label(record)
    case record
    when Expense, Income               then record.description
    when VendorInvoice, CustomerInvoice then record.invoice_number
    when Customer                      then record.display_name
    when Supplier                      then record.name
    when PayrollAdvance                then t("accounting.vouchers.advance_for",
                                              name: record.user&.name,
                                              default: "Advance — #{record.user&.name}")
    else record&.to_s
    end
  end

  def settled_path(record)
    case record
    when Expense         then admin_accounting_expense_path(record)
    when Income          then admin_accounting_income_path(record)
    when VendorInvoice   then admin_inventory_vendor_invoice_path(record)
    when CustomerInvoice then admin_sales_customer_invoice_path(record)
    when Customer        then admin_sales_customer_statement_path(record)
    when Supplier        then admin_inventory_supplier_path(record)
    when PayrollAdvance  then admin_user_path(record.user)
    end
  end

  # The party behind what a voucher settled, when that's knowable — an invoice
  # already names its supplier or customer, an advance its employee, and an
  # expense or income now carries its own party. Nil for anything else
  # (an equity adjustment, or on-account money settling nothing), which is the
  # caller's cue to fall back to the voucher's own party or its free-text
  # counterparty.
  def settled_party(record)
    case record
    when Expense, Income   then record.party
    when VendorInvoice     then record.supplier
    when CustomerInvoice   then record.customer
    when PayrollAdvance    then record.user
    when Customer, Supplier then record
    end
  end

  # What is still owed on it, where that means anything. A party has no single
  # outstanding amount in this context — money on account is not "against" one
  # thing — so it returns nil and the caller shows nothing.
  def settled_outstanding_cents(record)
    case record
    when Expense, Income                then record.outstanding_cents
    when VendorInvoice, CustomerInvoice then record.balance_due_cents
    end
  end

  # A voucher number is always a link to its document, and always looks like
  # one — the amber the rest of the accounting section uses for record links.
  def voucher_number_link(voucher, extra_class: nil)
    link_to voucher.number, admin_accounting_voucher_path(voucher),
            class: ["font-mono font-semibold text-amber-700 hover:text-amber-800 hover:underline",
                    extra_class].compact.join(" ")
  end

  # Link when there is somewhere to go, plain text otherwise.
  def settled_link(record, **options)
    label = settled_label(record)
    path  = settled_path(record)
    return label if path.blank?

    link_to label, path, **options
  end
end
