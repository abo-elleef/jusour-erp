# frozen_string_literal: true

module Accounting
  # Creates/updates/clears the cash delivery Expense linked to a vendor invoice.
  #
  # Only for delivery paid at receive. When the vendor bills delivery on the invoice
  # (freight_on_account), there is no cash movement and no Expense: the amount is
  # already in total_cents, so supplier AP carries it and the invoice journal entry
  # debits the delivery account directly. Any previously created cash Expense is
  # cleared, so switching an invoice from paid-now to on-account does not leave a
  # stale cash outflow behind.
  #
  # Cash delivery still never changes VI total, AP, or stock cost.
  #
  # Updates the same Expense row in place so `audited` keeps a change history.
  # Inventory receive/update callers may create this auto expense; same permission
  # gate as receiving the invoice itself.
  class SyncVendorInvoiceFreightService
    class Error < StandardError; end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(invoice:, user:, amount_cents:, treasury: nil, on_account: false)
      @invoice = invoice
      @user = user
      @amount_cents = amount_cents.to_i
      @treasury = treasury
      @on_account = on_account
    end

    def call
      if @amount_cents <= 0 || @on_account
        clear!
        return nil
      end

      raise Error, I18n.t("inventory.vendor_invoices.errors.freight_treasury_required") if @treasury.blank?
      unless payable_treasury?(@treasury)
        raise Error, I18n.t("inventory.vendor_invoices.errors.freight_treasury_invalid")
      end

      expense = existing_freight_expense
      attrs = {
        expense_category: category!,
        user: @user,
        treasury: @treasury,
        description: description,
        amount_cents: @amount_cents,
        expense_date: @invoice.received_on,
        recurrence: "one_time",
        is_auto_generated: true
      }

      if expense
        expense.update!(attrs)
      else
        expense = Expense.create!(
          attrs.merge(source_record: @invoice, company: @invoice.company)
        )
      end

      # Auto-generated expenses skip JE in Expense#sync_treasury_ledger; post explicitly.
      # Treasury cash movement still comes from Expense after_commit → sync_expense!.
      JournalEntryService.record_expense!(expense)
      @invoice.association(:freight_expense).reset
      expense
    end

    private

    def existing_freight_expense
      @invoice.reload_freight_expense
    end

    def clear!
      expense = existing_freight_expense
      return unless expense

      JournalEntryService.destroy_for_source!(expense)
      expense.destroy!
      @invoice.association(:freight_expense).reset
    end

    def category!
      ExpenseCategory.find_by!(name: ExpenseCategory::GOODS_DELIVERY_NAME, company: @invoice.company)
    end

    def description
      I18n.t(
        "inventory.vendor_invoices.freight_expense_description",
        invoice_number: @invoice.invoice_number,
        supplier: @invoice.supplier.name
      )
    end

    def payable_treasury?(treasury)
      treasury.company_id == @invoice.company_id &&
        treasury.treasury_type != "supplier_ap" &&
        treasury.active?
    end
  end
end
