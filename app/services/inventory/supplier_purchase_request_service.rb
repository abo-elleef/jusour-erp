# frozen_string_literal: true

module Inventory
  # Builds suggested purchase lines for a supplier: qty = max − balance.
  # Skips ingredients with max_quantity of zero or non-positive request qty.
  class SupplierPurchaseRequestService
    Line = Struct.new(
      :ingredient,
      :supplier_ingredient,
      :max_quantity,
      :balance,
      :requested_quantity,
      :estimated_cents,
      keyword_init: true
    )

    def initialize(supplier:, location: nil)
      @supplier = supplier
      @location = location
    end

    def call
      links = @supplier.supplier_ingredients
        .includes(ingredient: :unit_ref)
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
      requested = max_quantity - balance
      return if requested <= 0

      price = link.price_cents.to_i
      estimated = price.positive? ? (price * requested).round : nil

      Line.new(
        ingredient: link.ingredient,
        supplier_ingredient: link,
        max_quantity: max_quantity,
        balance: balance,
        requested_quantity: requested,
        estimated_cents: estimated
      )
    end
  end
end
