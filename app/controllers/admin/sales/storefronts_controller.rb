# frozen_string_literal: true

module Admin
  module Sales
    # Settings for the company's one storefront. Created on first save, so a
    # company that never opens this page has no row at all.
    class StorefrontsController < StorefrontBaseController
      before_action :set_storefront

      def show
        load_stats
      end

      def update
        @storefront.assign_attributes(storefront_params)

        if @storefront.save
          # A fresh upload in the same submit wins over its "remove" box.
          @storefront.logo.purge_later if remove?(:remove_logo) && !storefront_params.key?(:logo)
          @storefront.banner.purge_later if remove?(:remove_banner) && !storefront_params.key?(:banner)
          redirect_to admin_sales_storefront_path, notice: t("sales.storefront.flash.updated")
        else
          load_stats
          render :show, status: :unprocessable_entity
        end
      end

      private

      def set_storefront
        @storefront = Storefront.first_or_initialize
      end

      def load_stats
        @published_count = StorefrontListing.visible.count
        @listing_count = StorefrontListing.count
      end

      def remove?(key)
        ActiveModel::Type::Boolean.new.cast(params.dig(:storefront, key))
      end

      def storefront_params
        params.require(:storefront).permit(
          :enabled, :subdomain, :tagline, :tagline_ar, :phone, :whatsapp_number, :email, :address,
          :show_prices, :seo_description, :seo_description_ar, :logo, :banner,
          :primary_color, :accent_color, :font, :header_style,
          :announcement_enabled, :announcement_text, :announcement_text_ar, :announcement_url,
          :facebook_url, :instagram_url, :tiktok_url, :youtube_url, :map_url
        )
      end
    end
  end
end
