# frozen_string_literal: true

module Inventory
  class CompleteStockTakeJob < ApplicationJob
    queue_as :default

    def perform(stock_take_id, user_id)
      stock_take = StockTake.unscoped.find(stock_take_id)
      user = User.unscoped.find(user_id)

      with_company(stock_take.company) do
        return unless stock_take.status == "completing"

        begin
          apply_variances!(stock_take, user)
          stock_take.update!(status: "completed", completed_at: Time.current)
          broadcast_toast!(stock_take, success: true)
        rescue StandardError => e
          Rails.logger.error("[CompleteStockTakeJob] stock_take=#{stock_take_id} #{e.class}: #{e.message}")
          Rollbar.error(e, stock_take_id: stock_take_id, user_id: user_id) if defined?(Rollbar)
          stock_take.update!(status: "failed") if stock_take.reload.status == "completing"
          broadcast_toast!(stock_take, success: false)
        end
      end
    end

    private

    def apply_variances!(stock_take, user)
      ActiveRecord::Base.transaction do
        items = stock_take.stock_take_items.where(adjusted: false).includes(:ingredient).to_a
        unit_costs = Inventory::LocationUnitCost.map_for(
          ingredients: items.map(&:ingredient),
          location: stock_take.location
        )

        items.each do |item|
          next if item.variance.to_d.zero?

          attrs = {
            ingredient: item.ingredient,
            user: user,
            location: stock_take.location,
            quantity_delta: item.variance,
            adjustment_type: "cycle_count_correction",
            reason_notes: "Stock take ##{stock_take.id}",
            maintain_batches: true
          }
          if item.variance.to_d.positive?
            attrs[:batch_cost_per_unit_cents] = unit_costs.fetch(item.ingredient_id)
          end

          StockAdjustment.create!(attrs)
          item.update!(adjusted: true)
        end
      end
    end

    def broadcast_toast!(stock_take, success:)
      location_name = stock_take.location&.name.presence ||
                      I18n.t("inventory.stock_takes.index.all_locations")
      message = if success
                  I18n.t("flash.stock_take.completed_toast", location: location_name)
                else
                  I18n.t("flash.stock_take.failed_toast", location: location_name)
                end

      Turbo::StreamsChannel.broadcast_append_to(
        "admin_#{stock_take.company_id}",
        target: "toast-container",
        partial: "shared/toast",
        locals: { message: message, type: success ? :notice : :alert }
      )
    end
  end
end
