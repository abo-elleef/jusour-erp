# frozen_string_literal: true

module Inventory
  # Write a manufactured ingredient's master cost back from the weighted average
  # of its own remaining stock batches.
  #
  # The number already exists: RunManufacturingService rolls up the recipe's
  # input cost and stamps it on every output StockBatch. Nothing ever carried it
  # to ingredients.cost_per_unit_cents, which is the column the valuation report,
  # recipe costing and auto-COGS all read — so manufactured stock sat in the
  # report at whatever someone last typed, most often zero.
  #
  # Averaging the output's *own batches* rather than re-costing its recipe is
  # deliberate. It needs no walk of the template graph (one template's output can
  # be another's input, and only same-template self-reference is forbidden, so a
  # cycle is reachable), it reflects what was actually paid instead of what the
  # recipe says it should have cost, and multi-level manufacturing falls out for
  # free — by the time B is produced, A's batches already carry real costs.
  class SyncManufacturedCostService
    # skipped_reason is nil only when the cost actually moved.
    Result = Struct.new(
      :ingredient, :previous_cents, :new_cents, :batch_count, :skipped_reason,
      keyword_init: true
    ) do
      def changed?
        skipped_reason.nil?
      end
    end

    def self.call(ingredient:)
      new(ingredients: [ingredient]).call.fetch(ingredient.id)
    end

    # Every ingredient whose cost is marked derived, for the current company.
    def self.call_for_company
      new(ingredients: Ingredient.where(cost_source: "derived").to_a).call.values
    end

    # What the cost WOULD be, without writing it — for showing a hand-kept cost
    # against what the ingredient's own batches actually say. nil when no batch
    # has stock left.
    def self.preview(ingredient:)
      new(ingredients: [ingredient]).preview
    end

    def initialize(ingredients:)
      @ingredients = Array(ingredients).compact.uniq
    end

    # Returns { ingredient_id => Result }.
    def call
      return {} if @ingredients.empty?

      eligible, ineligible = @ingredients.partition { |ing| eligible?(ing) }
      results = ineligible.to_h { |ing| [ing.id, skip(ing, ineligible_reason(ing))] }

      averages = weighted_averages(eligible.map(&:id))

      eligible.each do |ingredient|
        results[ingredient.id] = sync(ingredient, averages[ingredient.id])
      end

      results
    end

    def preview
      weighted_averages(@ingredients.map(&:id)).values.first&.dig(:cents)
    end

    private

    # Only template outputs, and only where nobody has claimed the cost by hand.
    def eligible?(ingredient)
      ingredient.cost_source == "derived" && manufactured_ids.include?(ingredient.id)
    end

    def ineligible_reason(ingredient)
      manufactured_ids.include?(ingredient.id) ? :manual_cost : :not_manufactured
    end

    def manufactured_ids
      @manufactured_ids ||= ManufacturingTemplate
        .where(output_ingredient_id: @ingredients.map(&:id))
        .distinct
        .pluck(:output_ingredient_id)
        .to_set
    end

    def sync(ingredient, average)
      previous = ingredient.cost_per_unit_cents.to_i

      # No stock left to average. Keep the last known cost rather than dropping
      # to zero — a sold-out item is not a free item, and zeroing it would pull
      # the whole valuation down every time a batch runs out.
      return skip(ingredient, :no_batches) if average.nil?
      return skip(ingredient, :unchanged, new_cents: previous) if average[:cents] == previous

      ingredient.update!(cost_per_unit_cents: average[:cents], cost_synced_at: Time.current)

      Result.new(
        ingredient: ingredient,
        previous_cents: previous,
        new_cents: average[:cents],
        batch_count: average[:batch_count]
      )
    end

    def skip(ingredient, reason, new_cents: nil)
      Result.new(
        ingredient: ingredient,
        previous_cents: ingredient.cost_per_unit_cents.to_i,
        new_cents: new_cents || ingredient.cost_per_unit_cents.to_i,
        batch_count: 0,
        skipped_reason: reason
      )
    end

    # { ingredient_id => { cents:, batch_count: } } across every location.
    # cost_per_unit_cents is a global column, so this deliberately does not scope
    # by location the way Inventory::LocationUnitCost does.
    def weighted_averages(ids)
      return {} if ids.empty?

      rows = StockBatch
        .where(ingredient_id: ids)
        .with_stock
        .group(:ingredient_id)
        .pluck(
          Arel.sql("ingredient_id"),
          Arel.sql("SUM(quantity_remaining * cost_per_unit_cents)"),
          Arel.sql("SUM(quantity_remaining)"),
          Arel.sql("COUNT(*)")
        )

      rows.each_with_object({}) do |(ingredient_id, total_value, total_qty, batch_count), memo|
        quantity = total_qty.to_d
        next if quantity.zero?

        memo[ingredient_id] = {
          cents: (total_value.to_d / quantity).round,
          batch_count: batch_count
        }
      end
    end
  end
end
