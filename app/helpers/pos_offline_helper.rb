# frozen_string_literal: true

module PosOfflineHelper
  # Every string the offline register shows or prints, in the language of the
  # cashier who loaded the page. The page is cached, so the browser cannot ask the
  # server for a translation later — it has to arrive with the page.
  def offline_pos_labels_json
    I18n.t("pos.offline_mode").merge(
      receipt: I18n.t("printing.receipt"),
      pick_title: I18n.t("printing.production_ticket.pick_title"),
      order_notes: I18n.t("printing.receipt.order_notes"),
      fulfillment: I18n.t("order.fulfillment"),
      order_type: I18n.t("order.labels.order_type"),
      cash: I18n.t("payment.methods.cash"),
      all: I18n.t("actions.all"),
      combos: I18n.t("pos.categories.combos"),
      close: I18n.t("actions.close"),
      cancel: I18n.t("actions.cancel"),
      only_choice: I18n.t("promos.only_choice")
    ).to_json
  end
end
