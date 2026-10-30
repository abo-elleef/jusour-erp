# frozen_string_literal: true

module Public
  class StorefrontsController < StorefrontBaseController
    PER_PAGE = 24

    skip_before_action :set_storefront, :redirect_to_custom_domain, :set_locale_from_company, :load_storefront_categories,
      only: :not_found

    def show
      @query = params[:q].to_s.strip.first(100)
      @categories = IngredientCategory.where(id: StorefrontListing.visible.select("ingredients.ingredient_category_id")).ordered
      @category = @categories.find { |c| c.id == params[:category] }
      # Search, a category or a later page shows plain results; only the first
      # page of the bare home page is built from the admin's sections.
      @listing_mode = @category.present? || @query.present? || params[:page].to_i > 1

      scope = visible_listings
      scope = scope.where(ingredients: { ingredient_category_id: @category.id }) if @category
      if @query.present?
        term = "%#{StorefrontListing.sanitize_sql_like(@query)}%"
        scope = scope.where("storefront_listings.title ILIKE :term OR storefront_listings.title_ar ILIKE :term OR " \
                            "ingredients.name ILIKE :term OR ingredients.code ILIKE :term", term: term)
      end
      @pagy, @listings = pagy(:offset, scope.ordered, limit: PER_PAGE)

      load_section_data unless @listing_mode
    end

    def sitemap
      @listings = StorefrontListing.visible.ordered.select(:id, :slug, :updated_at)
      @pages = @storefront.live_pages
      render layout: false
    end

    def not_found
      head :not_found
    end

    private

    # Each product block gets its own short list; featured products are one
    # query shared by every featured block.
    def load_section_data
      @sections = @storefront.home_sections
      featured = @sections.select { |s| s.section_type == "featured_products" }
      if featured.any?
        limit = featured.map { |s| s.setting(:limit).to_i }.max
        @featured = visible_listings.where(featured: true).ordered.limit(limit).to_a
      end
      @section_products = @sections.select { |s| s.section_type == "category_products" }.to_h do |section|
        listings = visible_listings.where(ingredients: { ingredient_category_id: section.setting(:category_id) })
          .ordered.limit(section.setting(:limit).to_i)
        [section, listings.to_a]
      end
    end
  end
end
