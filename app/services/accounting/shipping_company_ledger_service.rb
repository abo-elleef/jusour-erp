# frozen_string_literal: true

module Accounting
  # Accounts-Receivable-shaped ledger for a shipping company: what they
  # currently owe us for cash-on-delivery shipments dispatched through them
  # but not yet remitted. Mirrors CustomerArLedgerService — a
  # "shipping_company_ar" ledger treasury, created on first dispatch, whose
  # balance rises on charge! and falls as vouchers settle it (see
  # RecordVoucherService#ensure_counterparty_treasuries!, which creates the
  # treasury before a voucher can post against it).
  class ShippingCompanyLedgerService
    def initialize(shipping_company)
      @shipping_company = shipping_company
    end

    # A COD shipment just dispatched: they now hold amount_cents of our money.
    # amount_cents is the invoice total; revenue is recognised here because
    # nothing recognised it at confirm (see Sales::ConfirmCustomerInvoiceService).
    def charge!(amount_cents:, user:, occurred_on:, source: nil, description: nil)
      treasury = ensure_treasury!
      treasury.with_lock do
        treasury.apply_balance_delta!(amount_cents)
        TreasuryTransaction.create!(
          treasury: treasury, user: user, amount_cents: amount_cents, kind: "shipping_company_charge",
          description: description || default_charge_description,
          occurred_on: occurred_on, source_record: source,
          balance_after_cents: treasury.balance_cents
        )
      end
      JournalEntryService.record_shipping_company_charge!(
        source: source, shipping_company: @shipping_company, date: occurred_on, user: user,
        amount_cents: amount_cents
      )
    end

    # Creates the ledger treasury on demand, so a shipping company nobody has
    # dispatched a COD order through yet never gets one.
    def ensure_treasury!
      @shipping_company.ar_treasury || create_treasury!
    end

    private

    def create_treasury!
      treasury = Treasury.create!(
        name: treasury_name, treasury_type: "shipping_company_ar",
        balance_cents: 0, opening_balance_cents: 0,
        active: true, is_default: false, position: 9999,
        company: @shipping_company.company, shipping_company: @shipping_company
      )
      @shipping_company.update_columns(treasury_id: treasury.id)
      treasury
    end

    def treasury_name
      base = "#{@shipping_company.name} — COD"
      return base unless Treasury.exists?(name: base, company: @shipping_company.company)

      "#{@shipping_company.name} — COD (#{@shipping_company.id[0, 6]})"
    end

    def default_charge_description
      I18n.t("accounting.shipping_company_ledger.dispatch_charge", name: @shipping_company.name,
             default: "COD dispatch — #{@shipping_company.name}")
    end
  end
end
