# frozen_string_literal: true

module Accounting
  # Cash and journal side of buying a machine.
  #
  # A fixed asset used to be a standalone register: recording one moved no money, so
  # the safe was reconciled with a separate Expense — booking a capital purchase as
  # an operating expense and double-counting it in the cash flow. The purchase is
  # the accounting event now.
  #
  # Paid outright: cash leaves the chosen treasury at acquisition.
  # On credit: nothing moves at acquisition; each installment moves its own cash.
  # Either way the journal debits the asset account, never an expense account — the
  # cost reaches the P&L later, as depreciation.
  class FixedAssetLedgerService
    class Error < StandardError; end

    def self.record_purchase!(asset:, user:)
      new.record_purchase!(asset, user)
    end

    def self.record_payment!(payment:, user:)
      new.record_payment!(payment, user)
    end

    def self.reverse_purchase!(asset:)
      new.reverse_purchase!(asset)
    end

    def self.reverse_payment!(payment:)
      new.reverse_payment!(payment)
    end

    def self.reverse_asset!(asset:)
      new.reverse_asset!(asset)
    end

    def record_purchase!(asset, user)
      ActiveRecord::Base.transaction do
        unless asset.on_credit?
          treasury = asset.paid_from_treasury
          raise Error, I18n.t("accounting.fixed_assets.errors.treasury_required") if treasury.blank?

          move_cash!(
            treasury: treasury, user: user, amount_cents: -asset.purchase_price_cents,
            kind: "fixed_asset_purchase", occurred_on: asset.purchase_date,
            source: asset, description: purchase_description(asset)
          )
        end

        JournalEntryService.record_fixed_asset_purchase!(asset)
      end
      asset
    end

    def record_payment!(payment, user)
      ActiveRecord::Base.transaction do
        move_cash!(
          treasury: payment.treasury, user: user, amount_cents: -payment.amount_cents,
          kind: "fixed_asset_payment", occurred_on: payment.payment_date,
          source: payment, description: payment_description(payment)
        )
        JournalEntryService.record_fixed_asset_payment!(payment)
      end
      payment
    end

    # Reverse a single installment payment and credit the treasury back.
    def reverse_payment!(payment)
      ActiveRecord::Base.transaction do
        TreasuryTransaction.where(source_record: payment, kind: "fixed_asset_payment").each do |txn|
          txn.treasury.with_lock do
            txn.treasury.apply_balance_delta!(-txn.amount_cents)
            txn.destroy!
          end
        end
        JournalEntryService.destroy_for_source!(payment)
      end
      payment
    end

    # Reverse all payments and the purchase itself, then destroy the asset.
    # This is the correct deletion path — calling asset.destroy! directly would
    # cascade-delete payments without reversing their treasury transactions.
    def reverse_asset!(asset)
      ActiveRecord::Base.transaction do
        asset.fixed_asset_payments.ordered.reverse_each do |payment|
          reverse_payment!(payment)
          payment.destroy!
        end
        reverse_purchase_internal!(asset)
        asset.destroy!
      end
    end

    # Undo the acquisition. Refuses once installments exist — those are separate cash
    # movements and have to be dealt with on their own rather than silently orphaned.
    def reverse_purchase!(asset)
      if asset.fixed_asset_payments.exists?
        raise Error, I18n.t("accounting.fixed_assets.errors.has_payments")
      end

      ActiveRecord::Base.transaction { reverse_purchase_internal!(asset) }
      asset
    end

    private

    def reverse_purchase_internal!(asset)
      TreasuryTransaction.where(source_record: asset, kind: "fixed_asset_purchase").each do |txn|
        txn.treasury.with_lock do
          txn.treasury.apply_balance_delta!(-txn.amount_cents)
          txn.destroy!
        end
      end
      JournalEntryService.destroy_for_source!(asset)
    end

    def move_cash!(treasury:, user:, amount_cents:, kind:, occurred_on:, source:, description:)
      treasury.with_lock do
        treasury.apply_balance_delta!(amount_cents)
        TreasuryTransaction.create!(
          treasury: treasury,
          user: user,
          amount_cents: amount_cents,
          kind: kind,
          description: description,
          occurred_on: occurred_on,
          source_record: source,
          balance_after_cents: treasury.balance_cents
        )
      end
    end

    def purchase_description(asset)
      I18n.t("accounting.fixed_assets.ledger.purchase", name: asset.name,
             default: "Fixed asset purchase — #{asset.name}")
    end

    def payment_description(payment)
      I18n.t("accounting.fixed_assets.ledger.payment", name: payment.fixed_asset.name,
             default: "Fixed asset payment — #{payment.fixed_asset.name}")
    end
  end
end
