# frozen_string_literal: true

module Public
  # Customer self-ordering from the public branch menu. Everything is priced on
  # the server; see OnlineOrders::SubmitService for the spam guards.
  class OnlineOrdersController < ApplicationController
    include PublicMenuScoped
    include OnlineOrderParams

    before_action :set_location, except: :show
    before_action :set_request, only: :show

    # Checkout preview: prices the cart and the delivery fee, saves nothing.
    def quote
      render_quote(@location, over_limit: ->(total_cents) { over_limit_message(total_cents) })
    end

    def create
      result = OnlineOrders::SubmitService.call(
        location: @location,
        params: order_params,
        ip: request.remote_ip,
        user_agent: request.user_agent
      )
      if result.ok?
        render json: { url: public_online_order_path(company_slug: @company.slug, token: result.request.token) },
               status: :created
      else
        render json: { error: result.error, message: online_order_error_message(result) }, status: :unprocessable_content
      end
    end

    def show
      @location = @request.location
    end

    private

    def set_request
      @request = OnlineOrderRequest.includes(:location, :order, :delivery_area).find_by!(token: params[:token])
    end

    # Same rule as OnlineOrders::SubmitService (the max itself is allowed), shown
    # in the checkout so the customer learns it before typing their details.
    def over_limit_message(total_cents)
      max = @location.online_max_order_cents
      return if max.blank? || total_cents <= max

      t("public.online_order.errors.too_large", max: helpers.format_money(max))
    end
  end
end
