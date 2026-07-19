# frozen_string_literal: true

# Training seed: top every active ingredient up to a target on-hand at the
# central kitchen, so workers can practice branch transfers end-to-end.
#
# It goes through the same path as a manual stock adjustment (location-scoped,
# maintain_batches: true), so each ingredient gets a real FIFO batch and is
# therefore *transferable* — not just a bare on-hand number.
#
# Safe to re-run: it only tops up the difference to the target (never duplicates
# or removes). Later, correct the real figures via a stock take on the kitchen.
#
# Run it:
#   bin/rails runner script/seed_training_stock.rb
# or in the console:
#   load "script/seed_training_stock.rb"
#
# Tweakables (env):
#   TARGET=100000   base-unit quantity to bring each ingredient up to
#   DRY_RUN=1       print what would change without writing anything

TARGET  = Integer(ENV.fetch("TARGET", "100000"))
DRY_RUN = ENV["DRY_RUN"].present?

company = Company.first
abort "No company found." if company.blank?
Current.company = company

kitchen = Location.active.central_kitchens.ordered.first
if kitchen.blank?
  puts "No active central kitchen found for #{company.name}."
  puts "Available locations: #{Location.active.pluck(:name, :location_type).inspect}"
  abort "Create/activate a central kitchen first, or edit this script to pick a location."
end

actor = User.where(company_id: company.id, role: "owner").first ||
        User.where(company_id: company.id, role: "manager").first ||
        User.where(company_id: company.id).order(:created_at).first
abort "No user found to attribute the adjustments to." if actor.blank?

ingredients = Ingredient.active.order(:name).to_a

puts "Company:        #{company.name}"
puts "Central kitchen: #{kitchen.name}"
puts "Attributed to:   #{actor.name} (#{actor.email})"
puts "Target on-hand:  #{TARGET} (base unit, per ingredient)"
puts "Active ingredients: #{ingredients.size}"
puts DRY_RUN ? "MODE: DRY RUN (no changes will be written)\n\n" : "MODE: APPLYING CHANGES\n\n"

seeded = 0
skipped = 0
failed  = 0

ingredients.each do |ingredient|
  current = IngredientLocation.find_by(ingredient: ingredient, location: kitchen)&.quantity_on_hand.to_d
  delta   = TARGET - current

  if delta <= 0
    skipped += 1
    next
  end

  if DRY_RUN
    puts "would add #{delta.to_s('F')} to #{ingredient.name} (now #{current.to_s('F')})"
    seeded += 1
    next
  end

  begin
    StockAdjustment.create!(
      ingredient: ingredient,
      user: actor,
      location: kitchen,
      quantity_delta: delta,
      adjustment_type: "manual_add",
      reason_notes: "Training seed — practice transfers",
      maintain_batches: true
    )
    seeded += 1
  rescue => e
    failed += 1
    puts "FAILED #{ingredient.name}: #{e.class} #{e.message}"
  end
end

puts "\nDone. seeded=#{seeded} skipped(already >= target)=#{skipped} failed=#{failed}"
puts "Reminder: correct the real quantities later via a stock take on #{kitchen.name}." unless DRY_RUN
