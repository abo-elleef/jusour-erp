# frozen_string_literal: true

module Inventory
  # Refresh one manufactured ingredient's derived cost after its batch mix has
  # changed. Enqueued by production runs and reversals; the nightly
  # inventory:sync_manufactured_costs task covers everything else that moves the
  # average (sales, transfers, stock takes) and re-runs anything this missed.
  class SyncManufacturedCostJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(ingredient_id)
      ingredient = Ingredient.unscoped.find(ingredient_id)

      with_company(ingredient.company) do
        Inventory::SyncManufacturedCostService.call(ingredient: ingredient)
      end
    end
  end
end
