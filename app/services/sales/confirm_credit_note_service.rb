# frozen_string_literal: true

module Sales
  # Confirms a draft credit note: reduces the customer's AR (Dr Sales Revenue /
  # Cr AR), returns the goods to stock when +restock+ is set, and — if the note
  # references an invoice — applies the credit against that invoice's balance.
  class ConfirmCreditNoteService
    class Error < StandardError; end

    def initialize(credit_note, user)
      @credit_note = credit_note
      @user = user
    end

    def call
      validate!
      customer = @credit_note.customer

      ActiveRecord::Base.transaction do
        restock! if @credit_note.restock?
        Accounting::CustomerArLedgerService.new(customer).credit!(
          amount_cents: @credit_note.total_cents, user: @user,
          occurred_on: @credit_note.credit_note_date, source: @credit_note
        )
        apply_to_invoice!
        @credit_note.update!(status: "confirmed", confirmed_at: Time.current)
      end
      @credit_note
    end

    private

    def validate!
      raise Error, I18n.t("sales.credit_notes.errors.not_draft", default: "Only a draft credit note can be confirmed.") unless @credit_note.draft?
      raise Error, I18n.t("sales.credit_notes.errors.no_lines", default: "Add at least one line before confirming.") if @credit_note.credit_note_lines.empty?
      raise Error, I18n.t("sales.credit_notes.errors.no_location", default: "A location is required.") if @credit_note.location.blank?
    end

    # Return the goods to the location's stock (rolls up on-hand and creates a
    # return batch so the stock is FIFO-costed and sellable again).
    def restock!
      @credit_note.credit_note_lines.includes(:ingredient).each do |line|
        quantity = line.base_quantity
        next if quantity <= 0

        StockAdjustment.create!(
          ingredient: line.ingredient, user: @user, location: @credit_note.location,
          quantity_delta: quantity, adjustment_type: "customer_return",
          reason_notes: "Returned via credit note #{@credit_note.credit_note_number}",
          maintain_batches: true
        )
      end
    end

    # When the note is tied to an invoice, the credit settles part of that
    # invoice's balance (balance_due drops, aging stays reconciled).
    def apply_to_invoice!
      invoice = @credit_note.customer_invoice
      return if invoice.blank?

      applied = [invoice.balance_due_cents, @credit_note.total_cents].min
      return if applied <= 0

      invoice.update!(amount_paid_cents: invoice.amount_paid_cents + applied)
      invoice.sync_payment_status!
    end
  end
end
