# frozen_string_literal: true

module ApplicationHelper
  def format_money(cents)
    return "$0.00" if cents.nil?

    Money.new(cents).format
  end

  def order_status_class(status)
    case status
    when "completed" then "bg-green-100 text-green-800"
    when "cancelled" then "bg-red-100 text-red-800"
    when "ready" then "bg-blue-100 text-blue-800"
    when "in_progress" then "bg-yellow-100 text-yellow-800"
    when "submitted" then "bg-indigo-100 text-indigo-800"
    else "bg-gray-100 text-gray-700"
    end
  end

  def admin_orders_filter_params
    params.permit(:date, q: {}).to_h.compact_blank
  end

  def pos_order_item_form_data
    { data: { turbo_stream: true } }
  end

  def order_type_class(order_type)
    case order_type
    when "delivery" then "bg-blue-100 text-blue-800"
    when "table" then "bg-purple-100 text-purple-800"
    else "bg-amber-100 text-amber-800"
    end
  end

  def user_role_class(role)
    case role
    when "owner" then "bg-purple-100 text-purple-800"
    when "manager" then "bg-blue-100 text-blue-800"
    when "cashier" then "bg-green-100 text-green-800"
    when "kitchen" then "bg-orange-100 text-orange-800"
    else "bg-gray-100 text-gray-700"
    end
  end
end
