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
end
