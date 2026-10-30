# frozen_string_literal: true

namespace :inventory do
  desc "Reconcile every ingredient's quantity_on_hand to the sum of its location quantities"
  task reconcile_on_hand: :environment do
    updated = 0
    Ingredient.unscoped.find_each do |ingredient|
      total = ingredient.ingredient_locations.sum(:quantity_on_hand)
      next if ingredient.quantity_on_hand.to_d == total.to_d

      ingredient.update_column(:quantity_on_hand, total)
      updated += 1
    end
    puts "Reconciled #{updated} ingredient(s) to their location totals."
  end

  desc "Back-fill balance_after on historical stock adjustments by replaying each ingredient+location sequence backwards from the current on-hand"
  task backfill_balance_after: :environment do
    updated = 0
    skipped = 0

    # Group adjustments by (ingredient_id, location_id).
    # nil location_id = global (no location scope).
    combos = StockAdjustment
      .where(balance_after: nil)
      .select(:ingredient_id, :location_id)
      .distinct
      .map { |r| [r.ingredient_id, r.location_id] }

    puts "Backfilling #{combos.size} ingredient+location combination(s)…"

    combos.each do |(ingredient_id, location_id)|
      ingredient = Ingredient.unscoped.find_by(id: ingredient_id)
      unless ingredient
        skipped += 1
        next
      end

      # Current authoritative balance for this scope.
      current_balance =
        if location_id.present?
          il = IngredientLocation.find_by(ingredient_id: ingredient_id, location_id: location_id)
          il&.quantity_on_hand.to_d
        else
          ingredient.quantity_on_hand.to_d
        end

      # Walk adjustments newest → oldest. balance_after of the newest = current_balance.
      # Then step back: balance before = balance_after - delta.
      adjustments = StockAdjustment
        .where(ingredient_id: ingredient_id, location_id: location_id)
        .order(created_at: :desc, id: :desc)

      running = current_balance
      rows = []
      adjustments.each do |adj|
        rows << { id: adj.id, balance_after: running }
        running = running - adj.quantity_delta.to_d
      end

      # Bulk-update in one shot per combo.
      rows.each do |row|
        StockAdjustment.where(id: row[:id]).update_all(balance_after: row[:balance_after])
      end
      updated += rows.size
    end

    puts "Done — #{updated} adjustment(s) updated, #{skipped} skipped (missing ingredient)."
  end

  # Refresh the master cost of manufactured ingredients from the weighted average
  # of their own remaining stock batches.
  #
  # Production runs and reversals sync their own output, but sales, transfers and
  # stock takes all draw batches down and move the average without touching the
  # ingredient — so this nightly sweep is what actually keeps the number honest,
  # and it makes every other trigger self-healing within a day.
  #
  #   bin/rails inventory:sync_manufactured_costs
  #
  # Schedule it at 04:30 UTC on Heroku Scheduler. The intent is 6:30 AM Cairo,
  # just past the BusinessDay boundary of 6 AM, so the previous day's production
  # is settled before the average is taken. Scheduler runs in UTC and Cairo shifts
  # with DST (UTC+2 winter, UTC+3 summer), so 04:30 UTC lands at 06:30 in winter
  # and 07:30 in summer — always after the boundary. Do NOT use 03:30 UTC: that
  # fires at 05:30 Cairo in winter, before the day has rolled over.
  #
  # Safe to re-run: it only writes when the average has actually moved, never
  # writes zero, and never touches a cost someone owns by hand (cost_source
  # "manual").
  desc "Refresh derived costs for manufactured ingredients from their stock batches"
  task sync_manufactured_costs: :environment do
    changed = 0
    examined = 0

    Company.find_each do |company|
      previous = Current.company
      Current.company = company
      begin
        results = Inventory::SyncManufacturedCostService.call_for_company
        next if results.empty?

        examined += results.size
        moved = results.select(&:changed?)
        changed += moved.size

        puts "#{company.name}: #{moved.size} changed of #{results.size} derived"
        moved.sort_by { |r| -r.new_cents }.each do |result|
          puts format("  %-30s %10.2f -> %10.2f  (%d batches)",
            result.ingredient.name,
            result.previous_cents / 100.0,
            result.new_cents / 100.0,
            result.batch_count)
        end
      ensure
        Current.company = previous
      end
    end

    puts "Done — #{changed} cost(s) updated across #{examined} derived ingredient(s)."
  end

  # Fills unit_cost_cents on stock movements recorded before it existed.
  #
  #   bin/rails inventory:backfill_movement_costs
  #
  # Movements tied to a batch get that batch's cost, which is exact: either the
  # row's own stock_batch_id, or the "ADJ-<id>" batch a manual add or stock-take
  # surplus created for itself. A transfer's outgoing row takes the cost of the
  # arrival it pairs with. Everything else gets the location's weighted
  # average as of today and is flagged unit_cost_estimated, because nothing
  # recorded what it was worth at the time. Safe to re-run: it only fills NULLs.
  desc "Back-fill unit_cost_cents on historical stock movements"
  task backfill_movement_costs: :environment do
    conn = ActiveRecord::Base.connection

    linked = conn.exec_update(<<~SQL.squish)
      UPDATE stock_adjustments sa
      SET unit_cost_cents = sb.cost_per_unit_cents
      FROM stock_batches sb
      WHERE sa.unit_cost_cents IS NULL AND sb.id = sa.stock_batch_id
    SQL

    self_created = conn.exec_update(<<~SQL.squish)
      UPDATE stock_adjustments sa
      SET unit_cost_cents = sb.cost_per_unit_cents
      FROM stock_batches sb
      WHERE sa.unit_cost_cents IS NULL
        AND sa.quantity_delta > 0
        AND sb.ingredient_id = sa.ingredient_id
        AND sb.batch_reference = 'ADJ-' || sa.id::text
    SQL

    # A transfer leaves one location at the cost it arrives at the other. The
    # two rows are written together — at one shared timestamp today, a few
    # milliseconds apart in older code — so the outgoing row takes its exact
    # cost from the closest matching arrival within a few seconds.
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
    transfers = conn.exec_update(<<~SQL.squish)
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

    estimated = 0
    combos = StockAdjustment.where(unit_cost_cents: nil).distinct.pluck(:location_id, :ingredient_id)
    combos.group_by(&:first).each do |location_id, pairs|
      location = location_id && Location.unscoped.find_by(id: location_id)
      ingredients = Ingredient.unscoped.where(id: pairs.map(&:last)).to_a
      costs = Inventory::LocationUnitCost.map_for(ingredients: ingredients, location: location)

      costs.each do |ingredient_id, cost|
        estimated += StockAdjustment
          .where(unit_cost_cents: nil, ingredient_id: ingredient_id, location_id: location_id)
          .update_all(unit_cost_cents: cost, unit_cost_estimated: true)
      end
    end

    puts "Exact from batch: #{linked + self_created} (#{linked} linked, #{self_created} self-created)."
    puts "Exact from the paired transfer arrival: #{transfers}."
    puts "Estimated at today's location average: #{estimated}."
    left = StockAdjustment.where(unit_cost_cents: nil).count
    puts "Still without a cost: #{left}." if left.positive?
  end
end
