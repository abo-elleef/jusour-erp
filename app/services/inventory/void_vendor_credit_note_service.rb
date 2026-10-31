# frozen_string_literal: true

module Inventory
  # Takes a confirmed credit note back off the books — the mirror image of
  # ConfirmVendorCreditNoteService, undoing each thing it posted:
  #
  #   1. the credit it applied to its invoice (so the invoice's balance due and
  #      payment status come back, and the invoice can be edited again once no
  #      other confirmed note is applied to it),
  #   2. the AP treasury movement and the Dr AP / Cr Purchases journal entry,
  #   3. for a goods return, the stock it sent back — re-added at the unit cost
  #      it left at, so inventory value returns to what it was.
  #
  # A draft posted nothing, so voiding one is a plain status change and does not
  # come through here.
  class VoidVendorCreditNoteService
    class Error < StandardError; end

    def self.call!(credit_note:, user:)
      new(credit_note, user).call!
    end

    def initialize(credit_note, user)
      @credit_note = credit_note
      @user        = user
    end

    def call!
      raise Error, I18n.t("inventory.vendor_credit_notes.errors.not_confirmed") unless @credit_note.confirmed?

      ActiveRecord::Base.transaction do
        @credit_note.lock!
        raise Error, I18n.t("inventory.vendor_credit_notes.errors.not_confirmed") unless @credit_note.confirmed?

        restore_stock! if @credit_note.goods_return?
        release_invoice! if @credit_note.vendor_invoice.present?
        Accounting::SupplierApLedgerService.reverse_credit_note!(credit_note: @credit_note, user: @user)
        @credit_note.update!(status: "void", voided_at: Time.current, voided_by: @user)
      end

      @credit_note
    end

    private

    def release_invoice!
      invoice = @credit_note.vendor_invoice
      invoice.with_lock do
        invoice.update!(credit_applied_cents: [invoice.credit_applied_cents - @credit_note.total_cents, 0].max)
        invoice.sync_payment_status!
      end
    end

    # One add-back per return movement, at that movement's own unit cost. A
    # goods return with no linked movements was confirmed before the link
    # existed and the backfill could not match it; restoring it from the lines
    # would guess at quantity and cost, so it is refused instead.
    def restore_stock!
      returns = @credit_note.stock_adjustments.removals.to_a
      raise Error, I18n.t("inventory.vendor_credit_notes.errors.stock_unlinked") if returns.empty?

      returns.each do |adjustment|
        StockAdjustment.create!(
          vendor_credit_note: @credit_note,
          ingredient: adjustment.ingredient,
          user: @user,
          location: adjustment.location,
          quantity_delta: adjustment.quantity_delta.to_d.abs,
          adjustment_type: "vendor_credit_note",
          unit_cost_cents: adjustment.unit_cost_cents,
          batch_cost_per_unit_cents: adjustment.unit_cost_cents,
          maintain_batches: true,
          reason_notes: I18n.t(
            "inventory.vendor_credit_notes.void_stock_adjustment_note",
            credit_note_number: @credit_note.credit_note_number,
            supplier: @credit_note.supplier.name,
            default: "Credit note #{@credit_note.credit_note_number} voided — #{@credit_note.supplier.name}"
          )
        )
      end
    end
  end
end
