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
    # not a figure to adopt as the standing cost.
    def base_scope
      VendorInvoiceLine
        .where(ingredient_id: @ingredient.id)
        .joins(:vendor_invoice)
        .where.not(vendor_invoices: { payment_status: "void" })
    end
  end
end
