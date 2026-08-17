# frozen_string_literal: true

module Inventory
  # Builds suggested purchase lines for a supplier: qty = max − balance.
  # Skips ingredients with max_quantity of zero or non-positive request qty.
  # When an ingredient has a purchase unit, quantities are shown in that unit
  # and requested qty is rounded up to whole purchase units.
  class SupplierPurchaseRequestService
    Line = Struct.new(
      :ingredient,
      :supplier_ingredient,
      :display_unit,
      :max_quantity,
      :balance,
      :requested_quantity,
      :requested_whole_units,
      :estimated_cents,
      keyword_init: true
    )

    def initialize(supplier:, location: nil)
      @supplier = supplier
      @location = location
    end

    def call
      links = @supplier.supplier_ingredients
        .includes(ingredient: [:unit_ref, { ingredient_units: :unit_ref }])
        .to_a
        .select { |link| link.ingredient.active? }

      balances = balances_for(links)

      lines = links.filter_map do |link|
        build_line(link, balances[link.ingredient_id])
      end

      lines.sort_by { |line| line.ingredient.name.to_s.downcase }
    end

    private

    def balances_for(links)
      if @location
        ils = IngredientLocation
          .where(location_id: @location.id, ingredient_id: links.map(&:ingredient_id))
          .index_by(&:ingredient_id)

        links.each_with_object({}) do |link, memo|
          il = ils[link.ingredient_id]
          memo[link.ingredient_id] = {
            balance: il&.quantity_on_hand.to_d,
            max_quantity: (il || link.ingredient).max_quantity.to_d
          }
        end
      else
        links.each_with_object({}) do |link, memo|
          ing = link.ingredient
          memo[ing.id] = {
            balance: ing.quantity_on_hand.to_d,
            max_quantity: ing.max_quantity.to_d
          }
        end
      end
    end

    def build_line(link, stock)
      max_quantity = stock[:max_quantity]
      return if max_quantity <= 0

      balance = stock[:balance]
      requested_base = max_quantity - balance
      return if requested_base <= 0

      ingredient = link.ingredient
      purchase_row = ingredient.purchase_unit_record
      price = link.price_cents.to_i

      if purchase_row
        factor = purchase_row.base_units_per_unit.to_d
        display_unit = purchase_row.unit
        balance_display = balance / factor
        max_display = max_quantity / factor
        requested_display = (requested_base / factor).ceil
        return if requested_display <= 0

        estimated = price.positive? ? (price * requested_display).round : nil
      else
        display_unit = ingredient.unit
        balance_display = balance
        max_display = max_quantity
        requested_display = requested_base
        estimated = price.positive? ? (price * requested_display).round : nil
      end

      Line.new(
        ingredient: ingredient,
        supplier_ingredient: link,
        display_unit: display_unit,
        max_quantity: max_display,
        balance: balance_display,
        requested_quantity: requested_display,
        requested_whole_units: purchase_row.present?,
        estimated_cents: estimated
      )
    end
  end
end
