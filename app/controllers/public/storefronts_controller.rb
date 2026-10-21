# frozen_string_literal: true

module Public
  class StorefrontsController < StorefrontBaseController
    PER_PAGE = 24

    skip_before_action :set_storefront, :set_locale_from_company, :load_storefront_categories, only: :not_found

    def show
      @query = params[:q].to_s.strip.first(100)
      @categories = IngredientCategory.where(id: StorefrontListing.visible.select("ingredients.ingredient_category_id")).ordered
      @category = @categories.find { |c| c.id == params[:category] }

      scope = visible_listings
      scope = scope.where(ingredients: { ingredient_category_id: @category.id }) if @category
      if @query.present?
        term = "%#{StorefrontListing.sanitize_sql_like(@query)}%"
        scope = scope.where("storefront_listings.title ILIKE :term OR storefront_listings.title_ar ILIKE :term OR " \
                            "ingredients.name ILIKE :term OR ingredients.code ILIKE :term", term: term)
      end

      @filtering = @category.present? || @query.present?
      @featured = @filtering ? [] : visible_listings.where(featured: true).ordered.limit(8).to_a
      @pagy, @listings = pagy(:offset, scope.ordered, limit: PER_PAGE)
    end

    def sitemap
      @listings = StorefrontListing.visible.ordered.select(:id, :slug, :updated_at)
      render layout: false
    end

    def not_found
      head :not_found
    end
  end
end
