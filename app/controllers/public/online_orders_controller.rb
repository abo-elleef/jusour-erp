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
        total: helpers.format_money(result.total_cents)
      }
    end

    def create
      result = OnlineOrders::SubmitService.call(
        location: @location,
        params: params.permit(:customer_name, :phone, :fulfillment, :delivery_area_id, :address, :note,
                              :website, :started_at, items: [:menu_item_id, :combo_id, :quantity, :notes, { modifier_ids: [] }]),
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

    def cart_items
      Array(params.permit(items: [:menu_item_id, :combo_id, :quantity, :notes, { modifier_ids: [] }])[:items])
        .map { |item| item.to_h }
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
