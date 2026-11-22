# frozen_string_literal: true

# Reading a checkout from online_order_controller.js, shared by the public menu
# (customers) and the call-center screen (staff typing for a customer).
module OnlineOrderParams
  extend ActiveSupport::Concern

  # The checkout posts multipart form data, because a prepaid order carries the
  # payment screenshot: the order itself arrives as one JSON field ("order") next
  # to the file. A plain JSON body (an older open tab) is still read.
  ORDER_FIELDS = [:customer_name, :phone, :fulfillment, :delivery_area_id, :address, :note, :payment_method,
                  :website, :started_at, { items: [:menu_item_id, :combo_id, :quantity, :notes, { modifier_ids: [] }] }].freeze

  private

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

  # Checkout preview: prices the cart and the delivery fee, saves nothing.
  # over_limit: a message when the total is over what this checkout may send.
  def render_quote(location, over_limit: ->(_total_cents) {})
    area = location.delivery_areas.active.find_by(id: params[:delivery_area_id]) if params[:fulfillment] == "delivery"
    result = Orders::QuoteService.call(location: location, items: cart_items, delivery_fee_cents: area&.fee_cents.to_i)
    render json: {
      lines: result.lines.map { |line| { name: line.name, quantity: line.quantity, total: helpers.format_money(line.line_total_cents - line.discount_cents) } },
      errors: result.errors.transform_values { |code| t("public.online_order.line_errors.#{code}") },
      subtotal: helpers.format_money(result.subtotal_cents - result.discount_cents),
      delivery_fee: helpers.format_money(result.delivery_fee_cents),
      total: helpers.format_money(result.total_cents),
      over_limit: over_limit.call(result.total_cents)
    }
  end

  def online_order_error_message(result)
    key = "public.online_order.errors.#{result.error}"
    case result.error
    when :too_large then t(key, max: helpers.format_money(result.details["max_cents"]))
    when :bad_items then t(key, count: result.details.size)
    else t(key, default: t("public.online_order.errors.generic"))
    end
  end
end
