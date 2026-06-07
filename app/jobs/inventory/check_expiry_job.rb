# frozen_string_literal: true

module Inventory
  class CheckExpiryJob < ApplicationJob
    queue_as :default

    def perform
      StockBatch.expiring_soon(2).includes(ingredient: :company).find_each do |batch|
        with_company(batch.ingredient.company) do
          ref = batch.batch_reference.presence || I18n.t("notifications.messages.no_batch_ref")
          Inventory::NotifyService.deliver_to_managers(
            ingredient: batch.ingredient,
            message_key: "batch_expiring",
            message_params: {
              name: batch.ingredient.name,
              ref: ref,
              expires_on: batch.expires_on.iso8601,
              remaining: batch.quantity_remaining,
              unit: batch.ingredient.unit
            }
          )
        end
      end
    end
  end
end
