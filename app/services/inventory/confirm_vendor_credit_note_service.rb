# frozen_string_literal: true

module Inventory
  class ConfirmVendorCreditNoteService
    def self.call!(credit_note:, user:)
      new(credit_note, user).call!
    end

    def initialize(credit_note, user)
      @credit_note = credit_note
      @user        = user
    end

    def call!
      raise ArgumentError, "Credit note is not postable" unless @credit_note.postable?

      ActiveRecord::Base.transaction do
        @credit_note.update!(status: "confirmed")
        return_stock! if @credit_note.goods_return?
        apply_to_invoice! if @credit_note.vendor_invoice.present?
        Accounting::SupplierApLedgerService.record_credit_note!(
          credit_note: @credit_note,
          user: @user
        )
      end

      @credit_note
    end

    private

    # Settle the invoice by the credited amount. Without this the supplier's AP
    # treasury drops by the credit while the invoice still shows the full balance
    # due — pay that off and the AP balance goes negative by the credit.
    def apply_to_invoice!
      invoice = @credit_note.vendor_invoice
      invoice.with_lock do
        invoice.update!(credit_applied_cents: invoice.credit_applied_cents + @credit_note.total_cents)
        invoice.sync_payment_status!
      end
    end

    # Send the goods back: one location-scoped adjustment per line, drawing the
    # quantity down FIFO through that location's batches. `maintain_batches`
    # is what keeps the batch ledger in step — without it the on-hand total
    # would fall while the batches it is made of stayed put.
    #
    # A location can legitimately go negative here (stock consumed before the
    # credit note was written up), so nothing blocks a short draw-down.
    def return_stock!
      @credit_note.vendor_credit_note_lines.each do |line|
        qty = line.base_quantity
        next if qty <= 0

        adjustment = StockAdjustment.new(
          ingredient: line.ingredient,
          user: @user,
          location: @credit_note.location,
          quantity_delta: -qty,
          adjustment_type: "vendor_credit_note",
          reason_notes: I18n.t(
            "inventory.vendor_credit_notes.stock_adjustment_note",
            credit_note_number: @credit_note.credit_note_number,
            supplier: @credit_note.supplier.name,
            default: "Returned on credit note #{@credit_note.credit_note_number} — #{@credit_note.supplier.name}"
          )
        )
        adjustment.maintain_batches = true
        adjustment.save!
      end
    end
  end
end
