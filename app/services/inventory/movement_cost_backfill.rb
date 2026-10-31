# frozen_string_literal: true

module Inventory
  # Fills stock_adjustments.unit_cost_cents for movements recorded before the
  # column existed (new movements are stamped live by StockAdjustment).
  #
  # Exact where history recorded the cost:
  #   1. the row's own stock_batch
  #   2. the "ADJ-<id>" batch a manual add or stock-take surplus created for itself
  #   3. a transfer_out takes the cost of the transfer_in it pairs with
  #
  # Everything else is reconstructed by replaying each item+location ledger in
  # order as a running weighted average — the average as it stood when the row
  # happened, which is what a live row would have recorded. Those rows are
  # flagged unit_cost_estimated. Today's average is only the last resort, for a
  # row with nothing before it to average.
  #
  # Re-running recomputes the estimated rows and leaves exact ones alone.
  class MovementCostBackfill
    Result = Struct.new(:linked, :self_created, :transfers, :estimated, keyword_init: true)

    def self.call = new.call

    def call
      StockAdjustment.where(unit_cost_estimated: true).update_all(unit_cost_cents: nil, unit_cost_estimated: false)

      Result.new(linked: fill_from_linked_batch, self_created: fill_from_self_created_batch,
                 transfers: fill_from_transfer_pairs, estimated: replay_running_average)
    end

    private

    def conn = ActiveRecord::Base.connection

    def fill_from_linked_batch
      conn.exec_update(<<~SQL.squish)
        UPDATE stock_adjustments sa
        SET unit_cost_cents = sb.cost_per_unit_cents
        FROM stock_batches sb
        WHERE sa.unit_cost_cents IS NULL AND sb.id = sa.stock_batch_id
      SQL
    end

    def fill_from_self_created_batch
      conn.exec_update(<<~SQL.squish)
        UPDATE stock_adjustments sa
        SET unit_cost_cents = sb.cost_per_unit_cents
        FROM stock_batches sb
        WHERE sa.unit_cost_cents IS NULL
          AND sa.quantity_delta > 0
          AND sb.ingredient_id = sa.ingredient_id
          AND sb.batch_reference = 'ADJ-' || sa.id::text
      SQL
    end

    # Both rows of a transfer are written together — at one shared timestamp
    # today, a few milliseconds apart in older code — so the outgoing row takes
    # the cost of the closest matching arrival within a few seconds.
    def fill_from_transfer_pairs
      pair = <<~SQL.squish
        FROM stock_adjustments arrival
        WHERE arrival.adjustment_type = 'transfer_in'
          AND arrival.unit_cost_cents IS NOT NULL
          AND arrival.unit_cost_estimated = false
          AND arrival.stock_transfer_id = sa.stock_transfer_id
          AND arrival.ingredient_id = sa.ingredient_id
          AND arrival.quantity_delta = -sa.quantity_delta
          AND arrival.created_at BETWEEN sa.created_at - interval '5 seconds'
                                     AND sa.created_at + interval '5 seconds'
      SQL
      conn.exec_update(<<~SQL.squish)
        UPDATE stock_adjustments sa
        SET unit_cost_cents = (
          SELECT arrival.unit_cost_cents #{pair}
          ORDER BY abs(extract(epoch FROM arrival.created_at - sa.created_at))
          LIMIT 1
        )
        WHERE sa.unit_cost_cents IS NULL
          AND sa.adjustment_type = 'transfer_out'
          AND EXISTS (SELECT 1 #{pair})
      SQL
    end

    def replay_running_average
      pending = StockAdjustment.where(unit_cost_cents: nil).distinct.pluck(:ingredient_id, :location_id)
      return 0 if pending.empty?

      fallback = todays_average(pending)
      costs = {}
      pending.each do |ingredient_id, location_id|
        replay(ingredient_id, location_id, fallback.dig(location_id, ingredient_id).to_i, costs)
      end

      costs.group_by(&:last).each do |cost, rows|
        StockAdjustment.where(id: rows.map(&:first)).update_all(unit_cost_cents: cost, unit_cost_estimated: true)
      end
      costs.size
    end

    # Walks one ledger oldest-first, carrying quantity and value. A row with no
    # cost moves at the average at that point; every row then updates the
    # average. While the balance is at or below zero there is nothing to average,
    # so the last known average carries forward, and the first receipt after it
    # resets the average to its own cost.
    def replay(ingredient_id, location_id, fallback_cents, costs)
      qty = 0.to_d
      value = 0.to_d
      last_avg = nil

      StockAdjustment.where(ingredient_id: ingredient_id, location_id: location_id)
        .order(:created_at, :id).pluck(:id, :quantity_delta, :unit_cost_cents)
        .each do |id, delta, cost|
          delta = delta.to_d
          if cost.nil?
            cost = (qty.positive? ? value / qty : last_avg || fallback_cents).round
            costs[id] = cost
          end

          was_positive = qty.positive?
          qty += delta
          value = if !qty.positive? then 0.to_d
                  elsif was_positive then value + (delta * cost)
                  else qty * cost
                  end
          last_avg = qty.positive? ? value / qty : cost
        end
    end

    # { location_id => { ingredient_id => cents } } — only for a row with no
    # history before it at all.
    def todays_average(pending)
      pending.group_by(&:last).to_h do |location_id, pairs|
        location = location_id && Location.unscoped.find_by(id: location_id)
        ingredients = Ingredient.unscoped.where(id: pairs.map(&:first)).to_a
        [location_id, LocationUnitCost.map_for(ingredients: ingredients, location: location)]
      end
    end
  end
end
