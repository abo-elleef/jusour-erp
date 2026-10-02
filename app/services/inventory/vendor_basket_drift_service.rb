# frozen_string_literal: true

module Inventory
  # What happened to purchase costs between two periods, and how much of the
  # change was price rather than buying differently.
  #
  # Source is vendor invoices — what was actually paid. supplier_price_histories
  # also holds prices, but mostly quoted/manual ones, and blending "what I was
  # quoted" with "what I paid" gives a number that answers neither.
  #
  # Drafts are excluded: a draft invoice is a save point, not a purchase.
  class VendorBasketDriftService
    # A month-on-month move past this is almost never a real price change — it is
    # a mistyped quantity or total. Found immediately in real data: one line
    # billed 12 units at ج.م.122,334 and reported cheese as up 4,576%.
    SUSPICIOUS_CHANGE_PCT = 100

    Row = Struct.new(:ingredient, :quantity, :prior_quantity, :spend_cents,
                     :prior_spend_cents, :price_cents, :prior_price_cents,
                     keyword_init: true) do
      def unit
        ingredient.unit
      end

      def bought_before?
        prior_quantity.positive?
      end

      def bought_now?
        quantity.positive?
      end

      def price_change_cents
        price_cents - prior_price_cents
      end

      # Percentage is how a price rise *feels*; price_impact_cents is what it
      # costs. A 30% rise on something bought twice a year is noise.
      def price_change_pct
        return nil unless bought_before? && prior_price_cents.positive?

        ((price_change_cents / prior_price_cents.to_d) * 100).round(1)
      end

      # Money attributable to price movement alone: last period's quantity at
      # this period's price. Zero for an item that is new or dropped, because
      # neither is a price change.
      def price_impact_cents
        (prior_quantity * price_change_cents).round
      end

      def spend_change_cents
        spend_cents - prior_spend_cents
      end

      # Flagged, never dropped: hiding a line would break the reconciliation
      # between these rows and real spend. The owner is told to verify the
      # invoice instead of being handed a fake price rise to negotiate over.
      def suspicious?
        pct = price_change_pct
        pct.present? && pct.abs >= SUSPICIOUS_CHANGE_PCT
      end
    end

    Result = Struct.new(:rows, :start_date, :end_date, :prior_start_date,
                        :prior_end_date, :spend_cents, :prior_spend_cents,
                        :price_effect_cents, :mix_effect_cents,
                        :invoice_count, :prior_invoice_count,
                        :unresolved_unit_lines, keyword_init: true) do
      def suspicious_rows
        rows.select(&:suspicious?)
      end
      def spend_change_cents
        spend_cents - prior_spend_cents
      end

      def spend_change_pct
        return nil unless prior_spend_cents.positive?

        ((spend_change_cents / prior_spend_cents.to_d) * 100).round(1)
      end
    end

    def initialize(start_date:, end_date:, supplier: nil, category: nil)
      @start_date = start_date
      @end_date = end_date
      @supplier = supplier
      @category = category
      # The comparison period is the same length immediately before, so a
      # 12-day range is never compared against a full month.
      length = (@end_date - @start_date).to_i + 1
      @prior_end_date = @start_date - 1
      @prior_start_date = @prior_end_date - (length - 1)
    end

    def call
      current = aggregate(@start_date, @end_date)
      prior = aggregate(@prior_start_date, @prior_end_date)

      ingredients = Ingredient.where(id: (current.keys | prior.keys)).index_by(&:id)
      rows = build_rows(current, prior, ingredients)

      spend = rows.sum(&:spend_cents)
      prior_spend = rows.sum(&:prior_spend_cents)
      price_effect = rows.sum(&:price_impact_cents)

      Result.new(
        rows: rows.sort_by { |row| [-row.price_impact_cents.abs, row.ingredient.name.to_s.downcase] },
        start_date: @start_date,
        end_date: @end_date,
        prior_start_date: @prior_start_date,
        prior_end_date: @prior_end_date,
        spend_cents: spend,
        prior_spend_cents: prior_spend,
        price_effect_cents: price_effect,
        # Derived, not summed independently: rounding each effect on its own
        # could leave the two failing to add up to the change they explain, and
        # a headline that does not reconcile is worse than no headline.
        mix_effect_cents: (spend - prior_spend) - price_effect,
        invoice_count: invoice_scope(@start_date, @end_date).count,
        prior_invoice_count: invoice_scope(@prior_start_date, @prior_end_date).count,
        unresolved_unit_lines: @unresolved_unit_lines.to_i
      )
    end

    private

    # invoice_date, not received_on: this is about what the priced document said,
    # and that is the date the price was agreed on. Voiding leaves draft: false,
    # so .posted alone isn't enough — a voided invoice never happened as far as
    # the ledger (and prices someone would want to compare against) is concerned.
    def invoice_scope(from, to)
      scope = VendorInvoice.posted.where.not(payment_status: "void").where(invoice_date: from..to)
      scope = scope.where(supplier_id: @supplier.id) if @supplier
      scope
    end

    # => { ingredient_id => { quantity: BigDecimal, spend_cents: Integer } }
    def aggregate(from, to)
      lines = VendorInvoiceLine
        .where(vendor_invoice_id: invoice_scope(from, to).select(:id))
        .includes(:unit_ref, ingredient: %i[ingredient_category ingredient_units])
      lines = lines.where(ingredient_id: category_ingredient_ids) if @category

      lines.each_with_object({}) do |line, totals|
        next if line.ingredient.blank?

        count_unresolved_unit(line)
        base_quantity = line.base_quantity
        next unless base_quantity.positive?

        bucket = (totals[line.ingredient_id] ||= { quantity: 0.to_d, spend_cents: 0 })
        bucket[:quantity] += base_quantity
        bucket[:spend_cents] += line.line_total_cents.to_i
      end
    end

    # base_quantity falls back to the raw figure when a line's unit no longer
    # resolves, which keeps invoices rendering but quietly mixes units here. The
    # count is surfaced so the report can say the basket is imperfect rather than
    # look precise.
    def count_unresolved_unit(line)
      @unresolved_unit_lines ||= 0
      return if line.unit.blank?
      return unless line.ingredient.base_units_per(line.unit).nil?

      @unresolved_unit_lines += 1
    end

    def build_rows(current, prior, ingredients)
      (current.keys | prior.keys).filter_map do |ingredient_id|
        ingredient = ingredients[ingredient_id]
        next if ingredient.nil?

        now = current[ingredient_id] || { quantity: 0.to_d, spend_cents: 0 }
        was = prior[ingredient_id] || { quantity: 0.to_d, spend_cents: 0 }

        price = unit_price(now)
        prior_price = unit_price(was)
        # An item bought in only one period has no price movement to measure, so
        # it carries the other period's price and lands wholly in the mix effect.
        price = prior_price if now[:quantity].zero?
        prior_price = price if was[:quantity].zero?

        Row.new(
          ingredient: ingredient,
          quantity: now[:quantity],
          prior_quantity: was[:quantity],
          spend_cents: now[:spend_cents],
          prior_spend_cents: was[:spend_cents],
          price_cents: price,
          prior_price_cents: prior_price
        )
      end
    end

    # Weighted average across every line in the period: total spend over total
    # base quantity, so a big delivery counts for more than a small one.
    def unit_price(bucket)
      bucket[:quantity].zero? ? 0.to_d : (bucket[:spend_cents] / bucket[:quantity])
    end

    def category_ingredient_ids
      Ingredient.where(ingredient_category_id: @category.id).select(:id)
    end
  end
end
