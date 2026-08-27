# frozen_string_literal: true

module Accounting
  # SPIKE — Accounts-Receivable ledger, the customer-side mirror of
  # SupplierApLedgerService.
  #
  # Each customer gets a "customer_ar" ledger treasury (created on first credit
  # sale) whose balance is the total this customer currently owes us.
  #
  #   ar_invoice (+) = receivable increased (we sold on credit)
  #   ar_payment (-) = receivable decreased (customer paid)
  #
  # Every balance move is kept in lockstep with the double-entry ledger via
  # JournalEntryService, exactly like the AP side.
  class CustomerArLedgerService
    def initialize(customer)
      @customer = customer
    end

    # Raise a receivable for a credit sale. amount_cents is the invoice total
    # (revenue + tax); revenue_cents/tax_cents split it for the P&L.
    def charge!(amount_cents:, user:, occurred_on:, source: nil, revenue_cents: nil, tax_cents: 0, description: nil)
      treasury = ensure_treasury!
      treasury.with_lock do
        treasury.apply_balance_delta!(amount_cents)
        TreasuryTransaction.create!(
          treasury: treasury, user: user, amount_cents: amount_cents, kind: "ar_invoice",
          description: description || default_charge_description,
          occurred_on: occurred_on, source_record: source,
          balance_after_cents: treasury.balance_cents
        )
      end
      JournalEntryService.record_customer_charge!(
        source: source, customer: @customer, date: occurred_on, user: user,
        amount_cents: amount_cents, revenue_cents: revenue_cents, tax_cents: tax_cents
      )
    end

    # Seed a customer's starting AR balance carried over from a previous system.
    # Raises the receivable without recognizing revenue (credits Equity).
    def open_balance!(amount_cents:, user:, occurred_on:, source: nil, description: nil)
      treasury = ensure_treasury!
      treasury.with_lock do
        treasury.apply_balance_delta!(amount_cents)
        TreasuryTransaction.create!(
          treasury: treasury, user: user, amount_cents: amount_cents, kind: "adjustment",
          description: description || I18n.t("accounting.ar_ledger.opening_balance",
                                             customer: @customer.display_name,
                                             default: "Opening balance — #{@customer.display_name}"),
          occurred_on: occurred_on, source_record: source,
          balance_after_cents: treasury.balance_cents
        )
      end
      JournalEntryService.record_customer_opening_balance!(
        source: source, customer: @customer, date: occurred_on, user: user, amount_cents: amount_cents
      )
    end

    # Reduce the receivable for a credit note / sales return (no cash moves).
    def credit!(amount_cents:, user:, occurred_on:, source: nil, revenue_cents: nil, tax_cents: 0, description: nil)
      treasury = ensure_treasury!
      treasury.with_lock do
        treasury.apply_balance_delta!(-amount_cents)
        TreasuryTransaction.create!(
          treasury: treasury, user: user, amount_cents: -amount_cents, kind: "ar_credit_note",
          description: description || I18n.t("accounting.ar_ledger.credit_note",
                                             customer: @customer.display_name,
                                             default: "Credit note — #{@customer.display_name}"),
          occurred_on: occurred_on, source_record: source,
          balance_after_cents: treasury.balance_cents
        )
      end
      JournalEntryService.record_customer_credit_note!(
        source: source, customer: @customer, date: occurred_on, user: user,
        amount_cents: amount_cents, revenue_cents: revenue_cents, tax_cents: tax_cents
      )
    end

    # Settle part (or all) of the balance. Money comes INTO the paying treasury.
    def settle!(treasury:, amount_cents:, user:, occurred_on:, source: nil, description: nil)
      ar = ensure_treasury!
      ar.with_lock do
        ar.apply_balance_delta!(-amount_cents)
        TreasuryTransaction.create!(
          treasury: ar, user: user, amount_cents: -amount_cents, kind: "ar_payment",
          description: description || default_settle_description,
          occurred_on: occurred_on, source_record: source,
          balance_after_cents: ar.balance_cents
        )
      end
      treasury.with_lock do
        treasury.apply_balance_delta!(amount_cents)
        TreasuryTransaction.create!(
          treasury: treasury, user: user, amount_cents: amount_cents, kind: "ar_payment",
          description: description || default_settle_description,
          occurred_on: occurred_on, source_record: source,
          balance_after_cents: treasury.balance_cents
        )
      end
      JournalEntryService.record_customer_receipt!(
        source: source, customer: @customer, treasury: treasury,
        date: occurred_on, user: user, amount_cents: amount_cents
      )
    end

    # Creates the AR ledger treasury for the customer on demand (mirrors
    # SupplierApLedgerService#ensure_treasury!), so ordinary POS customers who
    # never buy on credit never get one.
    def ensure_treasury!
      @customer.ar_treasury || create_treasury!
    end

    private

    def create_treasury!
      treasury = Treasury.create!(
        name: ar_treasury_name, treasury_type: "customer_ar",
        balance_cents: 0, opening_balance_cents: 0,
        active: true, is_default: false, position: 9999,
        company: @customer.company, customer: @customer
      )
      @customer.update_columns(treasury_id: treasury.id)
      treasury
    end

    def ar_treasury_name
      base = "#{@customer.display_name} — AR"
      return base unless Treasury.exists?(name: base, company: @customer.company)

      "#{@customer.display_name} — AR (#{@customer.id[0, 6]})"
    end

    def default_charge_description
      I18n.t("accounting.ar_ledger.credit_sale", customer: @customer.display_name,
             default: "Credit sale — #{@customer.display_name}")
    end

    def default_settle_description
      I18n.t("accounting.ar_ledger.payment_received", customer: @customer.display_name,
             default: "Payment received — #{@customer.display_name}")
    end
  end
end
