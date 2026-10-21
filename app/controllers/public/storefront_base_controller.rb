# frozen_string_literal: true

module Public
  # Shared lookup for the public storefront. The same pages answer two ways:
  # by path (/s/:company_slug/...) and on the storefront's own subdomain, where
  # there is no slug in the URL and the host picks the company. Links inside the
  # pages are built with storefront_*_path so they stay in whichever form the
  # visitor arrived by.
  class StorefrontBaseController < ApplicationController
    skip_before_action :authenticate_user!
    before_action :set_storefront
    before_action :set_locale_from_company
    before_action :load_storefront_categories

    layout "storefront"

    helper_method :storefront_home_path, :storefront_product_path, :storefront_product_url, :storefront_page_path,
      :storefront_page_url, :via_host?

    private

    def set_storefront
      if via_host?
        @storefront = Storefront.enabled_for_subdomain(Storefront.subdomain_from_host(request.host))
        raise ActiveRecord::RecordNotFound if @storefront.nil?

        @company = @storefront.company
        Current.company = @company
      else
        @company = Company.find_by!(slug: params[:company_slug], active: true)
        Current.company = @company
        @storefront = Storefront.find_by!(enabled: true)
      end

      raise ActiveRecord::RecordNotFound unless @company.feature_enabled?(:storefront)
    end

    def via_host?
      params[:company_slug].blank?
    end

    def storefront_home_path(**query)
      via_host? ? storefront_host_home_path(**query) : public_storefront_home_path(company_slug: @company.slug, **query)
    end

    def storefront_product_path(listing)
      if via_host?
        storefront_host_product_path(listing_slug: listing.slug)
      else
        public_storefront_product_path(company_slug: @company.slug, listing_slug: listing.slug)
      end
    end

    def storefront_product_url(listing)
      if via_host?
        storefront_host_product_url(listing_slug: listing.slug)
      else
        public_storefront_product_url(company_slug: @company.slug, listing_slug: listing.slug)
      end
    end

    def storefront_page_path(page)
      if via_host?
        storefront_host_page_path(page_slot: page.to_param_slot)
      else
        public_storefront_page_path(company_slug: @company.slug, page_slot: page.to_param_slot)
      end
    end

    def storefront_page_url(page)
      if via_host?
        storefront_host_page_url(page_slot: page.to_param_slot)
      else
        public_storefront_page_url(company_slug: @company.slug, page_slot: page.to_param_slot)
      end
    end

    def set_locale_from_company
      return if session[:locale].present? || params[:locale].present?

      locale = @company&.locale&.to_sym
      return unless locale && I18n.available_locales.include?(locale)

      session[:locale] = locale.to_s
      I18n.locale = locale
    end

    # Few rows per company; loaded once so every category name and tile on the
    # page comes from memory (see StorefrontHelper#storefront_category_name).
    def load_storefront_categories
      @storefront_categories = StorefrontCategory.includes(image_attachment: :blob).index_by(&:ingredient_category_id)
      @live_pages = @storefront.live_pages
    end

    def visible_listings
      StorefrontListing.visible.includes(ingredient: %i[ingredient_category unit_ref], images_attachments: :blob)
    end
  end
end
