# frozen_string_literal: true

module Inventory
  # Promotes a draft to a real request. Drafts are allowed to carry zero-quantity
  # placeholder lines, so this is where they get rejected — autosave only
  # validates changed children, which would let an untouched placeholder slip
  # through into a submitted transfer.
  class SubmitStockTransferService
    def initialize(transfer, user)
      @transfer = transfer
      @user = user
    end

    def call
      unless @transfer.can_submit?
        @transfer.errors.add(:status, I18n.t("inventory.stock_transfers.errors.cannot_submit"))
        raise ActiveRecord::RecordInvalid, @transfer
      end

      lines = @transfer.stock_transfer_lines.includes(:ingredient).to_a

      if lines.empty?
        @transfer.errors.add(:base, I18n.t("inventory.stock_transfers.errors.lines_required"))
        raise ActiveRecord::RecordInvalid, @transfer
      end

      incomplete = lines.select(&:awaiting_quantity?)
      if incomplete.any?
        @transfer.errors.add(:base, I18n.t(
          "inventory.stock_transfers.errors.draft_lines_incomplete",
          ingredients: incomplete.map { |l| l.ingredient.name }.to_sentence
        ))
        raise ActiveRecord::RecordInvalid, @transfer
      end

      ActiveRecord::Base.transaction do
        # A draft started days ago still carries its creation-day transferred_on,
        # and that date stamps the ledger via #occurred_at. Roll it forward so the
        # stock movement posts on the day the request actually goes out.
        @transfer.transferred_on = Date.current if @transfer.transferred_on.to_date < Date.current
        @transfer.status = "requested"
        @transfer.requested_by = @user if @transfer.requested_by.blank?
        @transfer.save!
      end

      @transfer
    end
  end
end
