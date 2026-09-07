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
        Accounting::SupplierApLedgerService.record_credit_note!(
          credit_note: @credit_note,
          user: @user
        )
      end

      @credit_note
    end
  end
end
