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
end
