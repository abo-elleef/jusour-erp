# frozen_string_literal: true

module Inventory
  class CheckExpiryJob < ApplicationJob
    queue_as :default

    def perform
      StockBatch.expiring_soon(2).includes(:ingredient).find_each do |batch|
        ref = batch.batch_reference.presence || "no ref"
        Inventory::NotifyService.deliver_to_managers(
          ingredient: batch.ingredient,
          message: "#{batch.ingredient.name} batch (#{ref}) expires on " \
                   "#{batch.expires_on.strftime('%b %d')}. " \
                   "#{batch.quantity_remaining} #{batch.ingredient.unit} remaining."
        )
      end
    end
  end
end
