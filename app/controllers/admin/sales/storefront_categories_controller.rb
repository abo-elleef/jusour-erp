# frozen_string_literal: true

module Admin
  module Sales
    # How inventory categories look on the storefront: photo, English/Arabic
    # names and descriptions. Lists every active category — there are only a
    # handful per company, so no pagination — and creates the StorefrontCategory
    # row on first save.
    class StorefrontCategoriesController < StorefrontBaseController
      before_action :set_category, only: %i[edit update]

      def index
        @categories = IngredientCategory.active.ordered
        @storefront_categories = StorefrontCategory.includes(image_attachment: :blob).index_by(&:ingredient_category_id)
        @listing_counts = StorefrontListing.visible.group("ingredients.ingredient_category_id").count
      end

      def edit; end

      def update
        @storefront_category.assign_attributes(category_params.except(:remove_image))

        if @storefront_category.save
          if ActiveModel::Type::Boolean.new.cast(category_params[:remove_image]) && !category_params.key?(:image)
            @storefront_category.image.purge_later
          end
          redirect_to admin_sales_storefront_categories_path, notice: t("sales.storefront_categories.flash.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_category
        @category = IngredientCategory.find(params[:id])
        @storefront_category = StorefrontCategory.find_or_initialize_by(ingredient_category: @category)
      end

      def category_params
        params.require(:storefront_category).permit(:title, :title_ar, :description, :description_ar, :image, :remove_image)
      end
    end
  end
end
