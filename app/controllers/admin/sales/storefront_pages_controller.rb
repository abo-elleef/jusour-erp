# frozen_string_literal: true

module Admin
  module Sales
    # Edit the storefront's four fixed info pages. Rows are created on first
    # save; a page goes live once it's published and has content.
    class StorefrontPagesController < StorefrontBaseController
      before_action :set_storefront
      before_action :set_page, only: %i[edit update]

      def index
        @pages = @storefront.pages.with_rich_text_body.with_rich_text_body_ar.index_by(&:slot)
      end

      def edit; end

      def update
        if @page.update(page_params)
          redirect_to admin_sales_storefront_pages_path, notice: t("sales.storefront_pages.flash.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_storefront
        @storefront = ::Storefront.first
        return if @storefront

        redirect_to admin_sales_storefront_path, alert: t("sales.storefront_sections.flash.settings_first")
      end

      def set_page
        slot = ::StorefrontPage.slot_from_param(params[:slot])
        raise ActiveRecord::RecordNotFound if slot.nil?

        @page = @storefront.pages.find_or_initialize_by(slot: slot)
      end

      def page_params
        params.require(:storefront_page).permit(:enabled, :title, :title_ar, :body, :body_ar)
      end
    end
  end
end
