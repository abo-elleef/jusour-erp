# frozen_string_literal: true

module Public
  # Customer self-ordering from the public branch menu. Everything is priced on
  # the server; see OnlineOrders::SubmitService for the spam guards.
  class OnlineOrdersController < ApplicationController
    include PublicMenuScoped

    before_action :set_location, except: :show
    before_action :set_request, only: :show

    # Checkout preview: prices the cart and the delivery fee, saves nothing.
    def quote
      area = @location.delivery_areas.active.find_by(id: params[:delivery_area_id]) if params[:fulfillment] == "delivery"
      result = Orders::QuoteService.call(location: @location, items: cart_items, delivery_fee_cents: area&.fee_cents.to_i)
      render json: {
        lines: result.lines.map { |line| { name: line.name, quantity: line.quantity, total: helpers.format_money(line.line_total_cents - line.discount_cents) } },
        errors: result.errors.transform_values { |code| t("public.online_order.line_errors.#{code}") },
        subtotal: helpers.format_money(result.subtotal_cents - result.discount_cents),
        delivery_fee: helpers.format_money(result.delivery_fee_cents),
        total: helpers.format_money(result.total_cents),
        over_limit: over_limit_message(result.total_cents)
      }
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
        render json: { error: result.error, message: error_message(result) }, status: :unprocessable_content
      end
    end

    def show
      @location = @request.location
    end

    private

    def set_request
      @request = OnlineOrderRequest.includes(:location, :order, :delivery_area).find_by!(token: params[:token])
    end

    # The checkout posts multipart form data, because a prepaid order carries the
    # payment screenshot: the order itself arrives as one JSON field ("order") next
    # to the file. A plain JSON body (an older open tab) is still read.
    ORDER_FIELDS = [:customer_name, :phone, :fulfillment, :delivery_area_id, :address, :note, :payment_method,
                    :website, :started_at, { items: [:menu_item_id, :combo_id, :quantity, :notes, { modifier_ids: [] }] }].freeze

    def order_params
      source = params[:order].is_a?(String) ? ActionController::Parameters.new(parse_order_json) : params
      permitted = source.permit(*ORDER_FIELDS)
      permitted[:payment_proof_image] = params[:payment_proof_image] if params[:payment_proof_image].respond_to?(:content_type)
      permitted
    end

    def parse_order_json
      parsed = JSON.parse(params[:order])
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def cart_items
      Array(params.permit(items: [:menu_item_id, :combo_id, :quantity, :notes, { modifier_ids: [] }])[:items])
        .map { |item| item.to_h }
    end

    # Same rule as OnlineOrders::SubmitService (the max itself is allowed), shown
    # in the checkout so the customer learns it before typing their details.
    def over_limit_message(total_cents)
      max = @location.online_max_order_cents
      return if max.blank? || total_cents <= max

      t("public.online_order.errors.too_large", max: helpers.format_money(max))
    end

    def error_message(result)
      key = "public.online_order.errors.#{result.error}"
      case result.error
      when :too_large then t(key, max: helpers.format_money(result.details["max_cents"]))
      when :bad_items then t(key, count: result.details.size)
      else t(key, default: t("public.online_order.errors.generic"))
      end
    end
  end
end
