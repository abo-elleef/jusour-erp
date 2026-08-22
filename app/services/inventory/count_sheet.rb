# frozen_string_literal: true

module Inventory
  # Rows for a printable physical count sheet at one location, scoped either to a
  # vendor or to an ingredient category.
  #
  # The row set deliberately mirrors what a stock take seeds
  # (StockTakesController#seed_stock_take_items): active ingredients that have an
  # IngredientLocation at this location. If the two diverge, counts written on
  # paper won't line up with the take they get typed into.
  class CountSheet
    Row = Struct.new(:ingredient, :link, :suppliers, :expected_quantity, keyword_init: true) do
      # The vendor's own name for the item — what is actually printed on the box.
      # Only meaningful on a vendor-scoped sheet, where there is one link.
      def vendor_product_name
        link&.vendor_product_name.presence
      end

      def vendor_sku
        link&.vendor_sku.presence
      end

      # For a sheet spanning vendors: whose box is this. Joined rather than reduced
      # to one "primary" vendor — nothing is summed here, so there is no reason to
      # force a partition the way the valuation report has to.
      def supplier_names
        Array(suppliers).map(&:name).compact_blank.uniq.sort.join(" / ").presence
      end
    end

    def initialize(location:, supplier: nil, category: nil)
      @location = location
      @supplier = supplier
      @category = category
    end

    # => [[group_label, [Row, ...]], ...]
    #
    # A vendor sheet groups by category, since that is roughly how the store is
    # laid out and the counter should walk it once. A category sheet is already one
    # group, so its rows come back alphabetically under the category name.
    def call
      return [] if @location.blank?
      return [] if @supplier.blank? && @category.blank?

      rows = build_rows
      return [] if rows.empty?

      @supplier ? group_by_category(rows) : [[@category.name, by_name(rows)]]
    end

    private

    def build_rows
      links_by_ingredient = supplier_links
      scope = IngredientLocation
        .where(location_id: @location.id)
        .includes(ingredient: [:ingredient_category, { supplier_ingredients: :supplier }])

      scope = scope.where(ingredient_id: links_by_ingredient.keys) if @supplier
      scope = scope.where(ingredient_id: category_ingredient_ids) if @category

      scope.select { |il| il.ingredient&.active? }.map do |il|
        Row.new(
          ingredient: il.ingredient,
          link: links_by_ingredient[il.ingredient_id],
          suppliers: il.ingredient.supplier_ingredients.map(&:supplier),
          expected_quantity: il.quantity_on_hand
        )
      end
    end

    def supplier_links
      return {} if @supplier.blank?

      @supplier.supplier_ingredients.index_by(&:ingredient_id)
    end

    def category_ingredient_ids
      Ingredient.where(ingredient_category_id: @category.id).select(:id)
    end

    # Categories by position then name, ingredients alphabetically inside each.
    def group_by_category(rows)
      rows
        .group_by { |row| row.ingredient.ingredient_category }
        .sort_by { |category, _| [category&.position.to_i, category&.name.to_s.downcase] }
        .map { |category, group| [category&.name.presence || I18n.t("inventory.stock_transfers.uncategorized"), by_name(group)] }
    end

    def by_name(rows)
      rows.sort_by { |row| row.ingredient.name.to_s.downcase }
    end
  end
end
