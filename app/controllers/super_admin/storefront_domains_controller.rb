# frozen_string_literal: true

module SuperAdmin
  # The success team connects a company's own domain (www.curelix.com) to its
  # storefront. Companies never set this themselves: it only works once the
  # domain is added on Heroku and its DNS points there.
  class StorefrontDomainsController < BaseController
    before_action :set_company
    before_action :set_storefront

    def edit; end

    def update
      if @storefront.update(custom_domain: params.dig(:storefront, :custom_domain))
        redirect_to super_admin_company_path(@company), notice: "Website domain updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_company
      @company = Company.unscoped.find(params[:company_id])
    end

    # Created here if the company hasn't opened its website settings yet; it
    # stays unpublished until the company turns it on.
    def set_storefront
      @storefront = Storefront.unscoped_by_company.find_or_initialize_by(company_id: @company.id)
    end
  end
end
