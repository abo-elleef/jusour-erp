# frozen_string_literal: true

module Accounting
  # Maintains the Accounts-Payable ledger treasury for each supplier.
  #
  # The AP treasury balance represents the total amount currently owed to this
  # supplier (unpaid + partially-paid invoices).
  #
  # Positive transactions (ap_invoice) = liability increased (we received goods)
  # Negative transactions (ap_payment) = liability decreased (we paid)
  class SupplierApLedgerService
    def self.record_invoice!(invoice:, user:)
      new(invoice.supplier).record_invoice!(invoice, user)
    end

    def self.record_payment!(payment:, user:)
      new(payment.vendor_invoice.supplier).record_payment!(payment, user)
    end

    def self.reverse_invoice!(invoice:, user:)
      new(invoice.supplier).reverse_invoice!(invoice, user)
    end

    def self.reverse_payment!(payment:, user:)
      new(payment.vendor_invoice.supplier).reverse_payment!(payment, user)
    end

    def self.record_credit_note!(credit_note:, user:)
      new(credit_note.supplier).record_credit_note!(credit_note, user)
    end

    def self.reverse_credit_note!(credit_note:, user:)
      new(credit_note.supplier).reverse_credit_note!(credit_note, user)
    end

    def initialize(supplier)
      @supplier = supplier
    end

    def record_invoice!(invoice, user)
      treasury = ensure_treasury!
      treasury.with_lock do
        treasury.apply_balance_delta!(invoice.total_cents)
        TreasuryTransaction.create!(
          treasury: treasury,
          user: user,
          amount_cents: invoice.total_cents,
          kind: "ap_invoice",
          description: ap_invoice_description(invoice),
          occurred_on: invoice.received_on,
          source_record: invoice,
          balance_after_cents: treasury.balance_cents
        )
      end
      JournalEntryService.record_vendor_invoice!(invoice)
    end

    def record_payment!(payment, user)
      treasury = ensure_treasury!
      invoice = payment.vendor_invoice
      treasury.with_lock do
        treasury.apply_balance_delta!(-payment.amount_cents)
        TreasuryTransaction.create!(
          treasury: treasury,
          user: user,
          amount_cents: -payment.amount_cents,
          kind: "ap_payment",
          description: ap_payment_description(invoice),
          occurred_on: payment.payment_date,
          source_record: payment,
          balance_after_cents: treasury.balance_cents
        )
      end
      JournalEntryService.record_vendor_invoice_payment!(payment)
    end

    def reverse_invoice!(invoice, user)
      TreasuryTransaction
        .where(source_record: invoice, kind: "ap_invoice")
        .find_each do |txn|
          txn.treasury.with_lock do
            txn.treasury.apply_balance_delta!(-txn.amount_cents)
            txn.destroy!
          end
        end
      JournalEntryService.reverse_vendor_invoice!(invoice)
    end

    def record_credit_note!(credit_note, user)
      treasury = ensure_treasury!
      treasury.with_lock do
        treasury.apply_balance_delta!(-credit_note.total_cents)
        TreasuryTransaction.create!(
          treasury: treasury,
          user: user,
          amount_cents: -credit_note.total_cents,
          kind: "ap_credit_note",
          description: I18n.t(
            "accounting.ap_ledger.credit_note_received",
            credit_note_number: credit_note.credit_note_number,
            supplier: @supplier.name,
            default: "Credit Note #{credit_note.credit_note_number} — #{@supplier.name}"
          ),
          occurred_on: credit_note.credit_note_date,
          source_record: credit_note,
          balance_after_cents: treasury.balance_cents
        )
      end
      JournalEntryService.record_vendor_credit_note!(credit_note)
    end

    def reverse_credit_note!(credit_note, _user)
      TreasuryTransaction
        .where(source_record: credit_note, kind: "ap_credit_note")
        .find_each do |txn|
          txn.treasury.with_lock do
            txn.treasury.apply_balance_delta!(-txn.amount_cents)
            txn.destroy!
          end
        end
      JournalEntryService.destroy_for_source!(credit_note)
    end

    def reverse_payment!(payment, _user)
      TreasuryTransaction
        .where(source_record: payment, kind: "ap_payment")
        .find_each do |txn|
          txn.treasury.with_lock do
            txn.treasury.apply_balance_delta!(-txn.amount_cents)
            txn.destroy!
          end
        end
      JournalEntryService.destroy_for_source!(payment)
    end

    # Creates the AP treasury for the supplier if it does not already exist.
    # Returns the existing treasury if already present.
    def ensure_treasury!
      @supplier.ap_treasury || create_treasury!
    end

    private

    def create_treasury!
      treasury = Treasury.create!(
        name: ap_treasury_name,
        treasury_type: "supplier_ap",
        balance_cents: 0,
        opening_balance_cents: 0,
        active: true,
        is_default: false,
        position: 9999,
        company: @supplier.company,
        supplier: @supplier
      )
      @supplier.update_columns(treasury_id: treasury.id)
      treasury
    end

    def ap_treasury_name
      base = "#{@supplier.name} — AP"
      return base unless Treasury.exists?(name: base, company: @supplier.company)

      "#{@supplier.name} — AP (#{@supplier.id[0, 6]})"
    end

    def ap_invoice_description(invoice)
      I18n.t(
        "accounting.ap_ledger.invoice_received",
        invoice_number: invoice.invoice_number,
        supplier: @supplier.name
      )
    end

    def ap_payment_description(invoice)
      I18n.t(
        "accounting.ap_ledger.payment_made",
        invoice_number: invoice.invoice_number,
        supplier: @supplier.name
      )
    end
  end
end
