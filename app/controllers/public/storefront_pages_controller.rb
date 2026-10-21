# frozen_string_literal: true

module Public
  # The storefront's fixed info pages (About, Contact, Delivery & returns,
  # Privacy). Only published pages with content are reachable.
  class StorefrontPagesController < StorefrontBaseController
    def show
      slot = StorefrontPage.slot_from_param(params[:page_slot])
      @page = @live_pages.find { |page| page.slot == slot }
      raise ActiveRecord::RecordNotFound if @page.nil?
    end
  end
end
