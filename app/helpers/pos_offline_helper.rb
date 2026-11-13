# frozen_string_literal: true

module PosOfflineHelper
  # Every string the offline register shows or prints, in the language of the
  # cashier who loaded the page. The page is cached, so the browser cannot ask the
  # server for a translation later — it has to arrive with the page.
  def offline_pos_labels_json
    I18n.t("pos.offline_mode").merge(
      receipt: I18n.t("printing.receipt"),
      pick_title: I18n.t("printing.production_ticket.pick_title"),
      ticket: I18n.t("printing.ticket"),
      order_notes: I18n.t("printing.receipt.order_notes"),
      fulfillment: I18n.t("order.fulfillment"),
      cash: I18n.t("payment.methods.cash"),
      all: I18n.t("actions.all"),
      combos: I18n.t("pos.categories.combos"),
      categories: I18n.t("pos.categories.label"),
      close: I18n.t("actions.close"),
      cancel: I18n.t("actions.cancel"),
      only_choice: I18n.t("promos.only_choice")
    ).to_json
  end

  # The order on the register right now, in the shape the offline register's cart
  # takes (see pos/_offline_handoff). When the internet drops, connectivity_controller saves it and the offline register opens
  # with it instead of an empty cart.
  #
  # Only an order nobody has paid for or sent to the kitchen is handed over: the
  # offline register prints tickets and takes the money itself, and doing either a
  # second time would double the food or the cash. Prices are not sent; the offline
  # register prices each line from its own menu snapshot, as it does every order.
  #
  # Always an object with `rendered_at`, so that of two copies on the page the
  # newer one wins even when it says "nothing to hand over" (`order: null`).
  def offline_handoff_json(order)
    { rendered_at: (Time.current.to_f * 1000).round, order: offline_handoff_order(order) }.to_json
  end

  def offline_handoff_order(order)
    return unless order&.persisted? && order.draft? && order.kitchen_sent_at.nil?
    return if order.payments.exists? || order.order_items.empty?

    {
      server_order_id: order.id,
      order_number: order.display_number,
      user_id: order.user_id,
      order_type: order.order_type,
      table_number: order.table_number.to_s,
      notes: order.notes.to_s,
      customer_name: order.customer&.name.to_s,
      customer_phone: order.customer&.phone.to_s,
      delivery_address: order.delivery_address.to_s,
      items: order.order_items.includes(:order_item_modifiers).order(:created_at, :id).map do |item|
        {
          menu_item_id: item.menu_item_id,
          combo_id: item.combo_id,
          quantity: item.quantity,
          notes: item.notes.presence,
          modifier_ids: item.order_item_modifiers.map(&:modifier_id)
        }
      end
    }
  end
end
