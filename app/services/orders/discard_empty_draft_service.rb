# frozen_string_literal: true

module Orders
  # Deletes a cart that was saved but never got an item: the register saves an
  # order as soon as the cashier attaches a customer, picks delivery or a table,
  # or types a note, and removing the last item leaves the order behind. Nothing
  # ever finished those carts, so every shift closed on a list of empty drafts.
  #
  # Only an order with nothing in it goes: still a draft, no items, no payment,
  # not a placed order reopened for edit. There is no money, stock, ticket or
  # journal behind such an order, so deleting it changes no figure anywhere.
  # Returns true when the order was deleted.
  class DiscardEmptyDraftService
    def self.call(order, user: nil)
      new(order, user: user).call
    end

    def initialize(order, user: nil)
      @order = order
      @user = user
    end

    def call
      return false unless @order&.persisted?

      @order.with_lock do
        return false unless self.class.discardable?(@order)

        AuditLogEntry.record!(
          action: "order.discard_empty", record: @order, user: @user || @order.user,
          changes_snapshot: {
            "order_number" => @order.order_number, "order_type" => @order.order_type,
            "customer_id" => @order.customer_id, "table_number" => @order.table_number,
            "cashier_id" => @order.user_id, "created_at" => @order.created_at
          }
        )
        @order.destroy!
      end
      true
    end

    def self.discardable?(order)
      order.draft? &&
        order.unlocked_for_edit_at.nil? &&
        !order.order_items.exists? &&
        !order.payments.exists?
    end
  end
end
