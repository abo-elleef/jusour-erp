# frozen_string_literal: true

module Admin
  module Sales
    # The products published on the storefront. A listing is a thin public layer
    # over an ingredient: name, category, unit and price still come from the
    # ingredient, so editing the product in Inventory updates the site.
    class StorefrontListingsController < StorefrontBaseController
      BULK_LIMIT = 500

      before_action :set_listing, only: %i[edit update destroy remove_image]

      def index
        @status = params[:status].presence_in(%w[published hidden])
        @category_id = params[:category_id].presence
        @query = params[:q].to_s.strip
        @sort = params[:sort].presence_in(StorefrontListing::INDEX_SORTABLE_COLUMNS) || StorefrontListing::INDEX_DEFAULT_SORT
        @direction = params[:dir].presence_in(%w[asc desc]) || StorefrontListing::INDEX_DEFAULT_SORT_DIRECTION

        base = StorefrontListing.joins(:ingredient)
        base = base.where(ingredients: { ingredient_category_id: @category_id }) if @category_id
        if @query.present?
          term = "%#{StorefrontListing.sanitize_sql_like(@query)}%"
          base = base.where("storefront_listings.title ILIKE :term OR ingredients.name ILIKE :term OR ingredients.code ILIKE :term",
            term: term)
        end

        # Tab counts follow the category/search filter but not the status tab
        # itself, so switching tabs doesn't look like data vanished.
        @all_count = base.count
        @published_count = base.where(published: true).count
        @hidden_count = @all_count - @published_count

        scope = base.includes(ingredient: %i[ingredient_category unit_ref], images_attachments: :blob)
        scope = scope.where(published: @status == "published") if @status
        scope = apply_sort(scope)

        @pagy, @listings = pagy(:offset, scope, limit: 50)
        @categories = IngredientCategory.ordered
        @storefront = Storefront.first
      end

      def new
        @listing = StorefrontListing.new(ingredient_id: params[:ingredient_id])
        load_form_data
      end

      def create
        @listing = StorefrontListing.new(listing_params.except(:images))
        @listing.images = new_images if new_images.any?

        if @listing.save
          redirect_to edit_admin_sales_storefront_listing_path(@listing), notice: t("sales.storefront_listings.flash.created")
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        @listing.assign_attributes(listing_params.except(:images, :ingredient_id))
        # Assigning to a has_many_attached replaces it, so keep the photos already
        # there and add the new uploads after them.
        @listing.images = @listing.ordered_images.map(&:blob) + new_images if new_images.any?

        if @listing.save
          redirect_to edit_admin_sales_storefront_listing_path(@listing), notice: t("sales.storefront_listings.flash.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @listing.destroy
        redirect_to admin_sales_storefront_listings_path, notice: t("sales.storefront_listings.flash.deleted")
      end

      def remove_image
        @listing.images.find(params[:attachment_id]).purge_later
        redirect_to edit_admin_sales_storefront_listing_path(@listing), notice: t("sales.storefront_listings.flash.image_removed")
      end

      # Publish many products at once — a distributor's catalog is hundreds of
      # items, and most only need the ingredient's own name and price.
      def bulk_new
        @category_id = params[:category_id].presence
        @query = params[:q].to_s.strip
        scope = unlisted_ingredients.includes(:ingredient_category, :unit_ref).order(:name)
        scope = scope.where(ingredient_category_id: @category_id) if @category_id
        if @query.present?
          term = "%#{Ingredient.sanitize_sql_like(@query)}%"
          scope = scope.where("ingredients.name ILIKE :term OR ingredients.code ILIKE :term", term: term)
        end
        @total_count = scope.count
        @ingredients = scope.limit(BULK_LIMIT)
        @categories = IngredientCategory.ordered
      end

      def bulk_create
        ids = Array(params[:ingredient_ids]).compact_blank
        created = 0
        StorefrontListing.transaction do
          unlisted_ingredients.where(id: ids).find_each do |ingredient|
            StorefrontListing.create!(ingredient: ingredient)
            created += 1
          end
        end

        redirect_to admin_sales_storefront_listings_path, notice: t("sales.storefront_listings.flash.bulk_created", count: created)
      end

      private

      def set_listing
        @listing = StorefrontListing.find(params[:id])
      end

      def unlisted_ingredients
        Ingredient.active.where.not(id: StorefrontListing.select(:ingredient_id))
      end

      def load_form_data
        @ingredient_options = unlisted_ingredients.order(:name).pluck(:id, :name, :code)
          .map { |id, name, code| { value: id, label: "#{name} (#{code})" } }
      end

      def new_images
        @new_images ||= Array(params.dig(:storefront_listing, :images)).compact_blank
      end

      def apply_sort(scope)
        case @sort
        when "name" then scope.order(Arel.sql("COALESCE(NULLIF(storefront_listings.title, ''), ingredients.name) #{@direction}"))
        when "category"
          scope.joins(ingredient: :ingredient_category).order("ingredient_categories.name #{@direction}", "ingredients.name")
        when "price" then scope.order("ingredients.selling_price_cents #{@direction}")
        when "updated_at" then scope.order("storefront_listings.updated_at #{@direction}")
        else scope.order("storefront_listings.position #{@direction}", "ingredients.name")
        end
      end

      def listing_params
        params.require(:storefront_listing).permit(:ingredient_id, :title, :description, :slug, :published, :featured,
          :position, images: [])
      end
    end
  end
end
