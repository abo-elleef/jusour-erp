# frozen_string_literal: true

module Orders
  # "Place order" at the register: the order leaves the cart, every station and
  # the expo get their tickets, the customer gets a receipt, and the items lock.
  #
  # The same button re-places an order a manager unlocked with the branch PIN: the
  # changes are saved, the lock comes back, and everything prints again. Station
  # tickets then carry an EDITED banner (edit_count) so the kitchen doesn't make
  # the order twice.
  #
  # Payment is separate. Paying a cart that was never placed still places it
  # (FinalizePaidService); paying a placed order leaves its tickets alone.
  class PlaceService
    def self.call(order, user:)
      new(order, user: user).call
    end

    def initialize(order, user:)
      @order = order
      @user = user
    end

    # Raises SubmitService::InvalidFulfillment when the order cannot go as it stands
    # (a table order with no table, a delivery with no address).
    def call
      if @order.draft?
        SubmitService.call(@order)
      elsif @order.editing_placed?
        replace!
      else
        return @order
      end

      Printing::PrintReceiptJob.perform_later(@order.id)
      @order
    end

    private

    def replace!
      SubmitService.validate_fulfillment!(@order)
      @order.with_lock do
        @order.recalculate_totals!
        @order.update!(unlocked_for_edit_at: nil, unlocked_for_edit_by: nil,
                       edit_count: @order.edit_count + 1)
      end
      AuditLogEntry.record!(action: "order.replace", record: @order, user: @user,
                            changes_snapshot: { "edit_count" => @order.edit_count })
      @order.broadcast_to_kds
      Printing::DispatchProductionPrintsJob.perform_later(@order.id)
    end
  end
end
