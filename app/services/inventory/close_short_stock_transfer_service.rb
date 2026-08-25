# frozen_string_literal: true

module Inventory
  # Accepts the shortfall on a partially received transfer and finishes it.
  #
  # Without this a transfer where some arrived and nobody intends to send the rest
  # had no terminal state — cancel is only reachable from `requested` — so it sat in
  # the Open queue indefinitely.
  #
  # Moves no stock: whatever arrived has already been posted, and whatever did not is
  # being written off deliberately, not returned. The reason is required because the
  # whole point is leaving a record of who accepted the gap.
  class CloseShortStockTransferService
    class Error < StandardError; end

    def initialize(transfer, user, reason:)
      @transfer = transfer
      @user = user
      @reason = reason.to_s.strip
    end

    def call
      unless @transfer.can_close_short?
        raise Error, I18n.t("inventory.stock_transfers.errors.cannot_close_short")
      end
      raise Error, I18n.t("inventory.stock_transfers.errors.close_short_reason_required") if @reason.blank?

      @transfer.update!(
        status: "completed",
        closed_short_at: Time.current,
        closed_short_by: @user,
        closed_short_reason: @reason
      )
      @transfer
    end
  end
end
