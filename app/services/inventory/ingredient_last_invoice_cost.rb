# frozen_string_literal: true

module Inventory
  # "What did we last actually pay for this ingredient?"
  #
  # The ingredient's master cost_per_unit_cents is maintained by hand and nothing
  # updates it when goods arrive, so it drifts away from what invoices say. This
  # backs the "fill from last invoice" action on the ingredient page: it reports the
  # most recent invoiced unit cost, which invoice it came from, and how many
  # invoices this ingredient appears on, so the confirmation can spell out the
  # change before anything is written.
  class IngredientLastInvoiceCost
    Result = Struct.new(:unit_cost_cents, :invoice, :invoice_count, keyword_init: true)

    # A line whose computed unit cost is zero (zero base quantity, or a zero-value
    # line) is skipped rather than offered — filling the master cost with 0 is
    # exactly the silent wipe this feature must not cause. Bounded so one odd
    # ingredient can't walk its whole invoice history.
    LOOKBACK = 25

    # Batch version: returns { ingredient_id => Result|nil } in 2 queries
    # instead of N*2. Use this when building the map for a whole collection
    # (e.g. the valuation report).
    def self.batch_call(ingredients)
      ids = ingredients.map(&:id)
      return {} if ids.empty?

      base = VendorInvoiceLine
        .where(ingredient_id: ids)
        .joins(:vendor_invoice)
        .where(vendor_invoices: { draft: false })
        .where.not(vendor_invoices: { payment_status: "void" })
        .includes(:vendor_invoice)
        .order(Arel.sql("vendor_invoices.invoice_date DESC, vendor_invoices.created_at DESC"))

      # Group LOOKBACK candidates per ingredient in Ruby — one query total.
      candidates_by_ingredient = Hash.new { |h, k| h[k] = [] }
      base.each do |line|
        bucket = candidates_by_ingredient[line.ingredient_id]
        bucket << line if bucket.size < LOOKBACK
      end

      # Count distinct invoices per ingredient from what we already loaded.
      invoice_counts = candidates_by_ingredient.transform_values do |lines|
        lines.map(&:vendor_invoice_id).uniq.size
      end

      ingredients.index_with do |ingredient|
        lines = candidates_by_ingredient[ingredient.id]
        line  = lines.detect { |l| l.base_unit_price_cents.to_i.positive? }
        next nil if line.nil?

        Result.new(
          unit_cost_cents: line.base_unit_price_cents,
          invoice:         line.vendor_invoice,
          invoice_count:   invoice_counts[ingredient.id].to_i
        )
      end
    end

    def initialize(ingredient)
      @ingredient = ingredient
    end

    # => Result, or nil when there is no usable invoiced price.
    def call
      line = candidate_lines.detect { |candidate| candidate.base_unit_price_cents.to_i.positive? }
      return nil if line.nil?

      Result.new(
        unit_cost_cents: line.base_unit_price_cents,
        invoice: line.vendor_invoice,
        invoice_count: invoice_count
      )
    end

    private

    def candidate_lines
      base_scope
        .includes(:vendor_invoice)
        .order(Arel.sql("vendor_invoices.invoice_date DESC, vendor_invoices.created_at DESC"))
        .limit(LOOKBACK)
    end

    def invoice_count
      base_scope.distinct.count(:vendor_invoice_id)
    end

    # Voided invoices are excluded: their accounting was undone, so their price is
    # not a figure to adopt as the standing cost. Drafts too — nothing was received
    # at that price yet, so it is not a price we have actually paid.
    def base_scope
      VendorInvoiceLine
        .where(ingredient_id: @ingredient.id)
        .joins(:vendor_invoice)
        .where(vendor_invoices: { draft: false })
        .where.not(vendor_invoices: { payment_status: "void" })
    end
  end
end
