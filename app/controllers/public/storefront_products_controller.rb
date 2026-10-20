# frozen_string_literal: true

module Public
  class StorefrontProductsController < StorefrontBaseController
    def show
      @listing = visible_listings.find_by!(slug: params[:listing_slug])
      @related = visible_listings
        .where(ingredients: { ingredient_category_id: @listing.ingredient.ingredient_category_id })
        .where.not(id: @listing.id).ordered.limit(4)
    end
  end
end
