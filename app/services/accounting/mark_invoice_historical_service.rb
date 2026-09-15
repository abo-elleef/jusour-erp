# frozen_string_literal: true

module Accounting
  # Marks an invoice as settled by a payment that was recorded against the
  # supplier's AP balance instead of against the invoice itself.
  #
  # Before supplier payments were forced through invoices (see PaySupplierService),
  # a direct AP payment moved the balance and left every invoice it had actually
  # paid still reading as unpaid. The cash is already recorded — an Expense left
  # the treasury, the AP ledger already dropped — so this writes the invoice side
  # ONLY. No expense, no treasury transaction, no journal entry: creating any of
  # those would count the same money twice.
  #
  # The guard rail is the supplier's AP balance. Marking can never take the
  # supplier's open invoices below what their ledger says is still owed, so the
  # identity "open invoices == AP balance" is approached but never crossed.
  class MarkInvoiceHistoricalService
    class Error < StandardError; end

    def initialize(invoice:, user:, amount_cents: nil)
      @invoice = invoice
      @user = user
      # Default to closing the invoice outright — the common case. A smaller
      # amount is for the one invoice per supplier where the payments ran out
      # partway, which is what makes the remaining invoices add back up to the
      # AP balance exactly.
      @amount_cents = (amount_cents || invoice.balance_due_cents).to_i
    end

    # The most that may still be marked historical across this supplier, i.e. how
    # far the invoices currently overstate what the AP ledger says is owed.
    def self.remaining_overstatement_cents(supplier)
      open_total = PaySupplierService.open_invoices_for(supplier).sum(&:balance_due_cents)
      [open_total - supplier.ap_balance_cents, 0].max
    end

    def call
      raise Error, I18n.t("inventory.vendor_invoices.historical.errors.not_payable") unless @invoice.payable?
      raise Error, I18n.t("inventory.vendor_invoices.historical.errors.amount_zero") if @amount_cents <= 0

      if @amount_cents > @invoice.balance_due_cents
        raise Error, I18n.t("inventory.vendor_invoices.historical.errors.exceeds_balance_due",
          balance: money(@invoice.balance_due_cents))
      end

      cap = self.class.remaining_overstatement_cents(@invoice.supplier)
      if cap <= 0
        raise Error, I18n.t("inventory.vendor_invoices.historical.errors.nothing_overstated",
          balance: money(@invoice.supplier.ap_balance_cents))
      end
      if @amount_cents > cap
        raise Error, I18n.t("inventory.vendor_invoices.historical.errors.exceeds_overstatement",
          cap: money(cap))
      end

      @invoice.update!(
        historical_settled_cents: @invoice.historical_settled_cents + @amount_cents,
        historical_settled_at: Time.current,
        historical_settled_by: @user
      )
      @invoice.sync_payment_status!
      @invoice
    end

    # Puts the invoice back the way it was. A marking is a judgement call about
    # which invoice an old payment belonged to, so it has to be reversible.
    def undo
      raise Error, I18n.t("inventory.vendor_invoices.historical.errors.not_historical") unless @invoice.historical?

      @invoice.update!(historical_settled_cents: 0, historical_settled_at: nil, historical_settled_by: nil)
      @invoice.sync_payment_status!
      @invoice
    end

    private

    def money(cents)
      ApplicationController.helpers.format_money(cents)
    end
  end
end
