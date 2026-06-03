# frozen_string_literal: true

module ApplicationHelper
  def html_lang
    I18n.locale.to_s
  end

  def html_dir
    I18n.locale == :ar ? "rtl" : "ltr"
  end

  def rtl?
    html_dir == "rtl"
  end

  def accounting_nav_active?(*controller_names)
    controller_names.include?(controller.controller_name)
  end

  def accounting_shift_label(shift)
    t("accounting.shifts.#{shift}", default: shift.to_s.humanize)
  end

  def accounting_drawer_status(status)
    t("accounting.cash_drawer.statuses.#{status}", default: status.to_s.humanize)
  end

  def accounting_integration_status(status)
    t("accounting.integrations.statuses.#{status}", default: status.to_s.humanize)
  end

  def accounting_month_abbr(month)
    I18n.t("date.abbr_month_names")[month]
  end

  def accounting_expense_category_type(type)
    t("accounting.expense_categories.types.#{type}", default: type.to_s.humanize)
  end

  def chart_money_prefix
    Money.new(0).format(symbol: true, no_cents: true, locale: I18n.locale).gsub(/[\d.,\s\u00a0]/, "")
  end

  def admin_page_title(page_action = nil)
    page_action ||= action_name
    if controller_name == "reports"
      return t("admin.pages.reports.#{page_action}_title", default: page_action.humanize)
    end

    key = case page_action
          when "new" then "new"
          when "edit" then "edit"
          when "low_stock" then "low_stock"
          when "suggestions" then "suggestions"
          else "title"
          end
    scope = controller_path.delete_prefix("admin/").delete_prefix("inventory/")
    t("admin.pages.#{scope}.#{key}", default: controller_name.humanize)
  end

  def locale_button_class(locale)
    base = "px-2.5 py-1.5 rounded-lg transition-colors"
    active = I18n.locale == locale
    active ? "#{base} bg-gray-900 text-white" : "#{base} text-gray-600 hover:bg-gray-100"
  end

  def format_money(cents)
    return Money.new(0).format(locale: I18n.locale) if cents.nil?

    Money.new(cents).format(locale: I18n.locale)
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

  def order_status_border_class(status)
    case status
    when "completed" then "border-green-200"
    when "cancelled" then "border-red-200"
    when "ready" then "border-blue-200"
    when "in_progress" then "border-yellow-200"
    when "submitted" then "border-indigo-200"
    else "border-gray-200"
    end
  end

  def payment_status_class(status)
    case status
    when "completed" then "bg-green-100 text-green-800"
    when "refunded" then "bg-gray-100 text-gray-700"
    when "partially_refunded" then "bg-amber-100 text-amber-900"
    when "pending" then "bg-yellow-100 text-yellow-800"
    when "failed" then "bg-red-100 text-red-800"
    else "bg-gray-100 text-gray-700"
    end
  end

  def payment_status_border_class(status)
    case status
    when "completed" then "border-green-200"
    when "refunded" then "border-gray-200"
    when "partially_refunded" then "border-amber-200"
    when "pending" then "border-yellow-200"
    when "failed" then "border-red-200"
    else "border-gray-200"
    end
  end

  def admin_orders_filter_params
    params.permit(:date, :focus, q: {}).to_h.compact_blank
  end

  def admin_orders_filter_url(**extra)
    payload = admin_orders_filter_params.deep_merge(extra.deep_stringify_keys)
    payload.delete("focus") if extra.key?(:focus) && extra[:focus].nil?
    payload.delete("date") if extra.key?(:date) && extra[:date].nil?
    admin_orders_path(payload.compact_blank)
  end

  def order_status_label(status)
    I18n.t("order.statuses.#{status}", default: status.to_s.humanize)
  end

  def customer_loyalty_points_label(points)
    t("customers.loyalty_points", count: points.to_i)
  end

  def order_type_label(order_type)
    I18n.t("order.types.#{order_type}", default: order_type.to_s.humanize)
  end

  def user_role_label(role)
    I18n.t("user.roles.#{role}", default: role.to_s.humanize)
  end

  def payment_method_label(method)
    I18n.t("payment.methods.#{method}", default: method.to_s.humanize)
  end

  def order_payment_summary(order)
    if order.status.in?(%w[draft cancelled])
      return tag.span("—", class: "text-gray-400")
    end
    if order.fully_paid?
      return tag.span(t("order.payment.paid"), class: "text-green-700 text-xs font-medium")
    end
    if order.amount_due_cents.positive?
      return tag.span(t("order.payment.due", amount: format_money(order.amount_due_cents)), class: "text-amber-700 text-xs font-medium")
    end

    tag.span(t("order.payment.paid"), class: "text-green-700 text-xs font-medium")
  end

  def orders_stat_card_class(active)
    base = "bg-white rounded-2xl p-4 border transition-colors block hover:border-gray-300"
    active ? "#{base} border-amber-500 bg-amber-50/40 ring-2 ring-amber-500/15" : "#{base} border-gray-200"
  end

  def pos_order_item_form_data
    { data: { turbo_stream: true } }
  end

  def ingredient_stock_row_class(ingredient)
    case ingredient.stock_status
    when :out then "bg-red-50"
    when :low then "bg-red-50"
    when :near then "bg-yellow-50"
    else ""
    end
  end

  def supplier_ingredient_price_dollars(link)
    return nil if link.price_cents.zero? && link.new_record?

    (link.price_cents.to_d / 100).round(2)
  end

  def ingredient_cost_dollars(ingredient)
    return nil if ingredient.cost_per_unit_cents.zero? && ingredient.new_record?

    (ingredient.cost_per_unit_cents.to_d / 100).round(2)
  end

  def purchase_order_item_unit_price_dollars(item)
    cents = item.unit_price_cents.to_i
    return nil if cents.zero? && item.new_record?

    (cents.to_d / 100).round(2)
  end

  def ingredient_stock_level_percent(ingredient)
    return 100 if ingredient.reorder_threshold.zero?

    [(ingredient.quantity_on_hand / ingredient.reorder_threshold * 100).round, 0].max
  end

  def ingredient_stock_bar_class(ingredient)
    case ingredient.stock_status
    when :out then "bg-red-500"
    when :low then "bg-red-500"
    when :near then "bg-amber-500"
    else "bg-green-500"
    end
  end

  def ingredient_expiring_label(ingredient, days: StockBatch::EXPIRING_SOON_DAYS)
    cutoff = Date.current + days.days
    date = ingredient.stock_batches
      .select { |b| b.quantity_remaining.to_d.positive? && b.expires_on.present? && b.expires_on <= cutoff }
      .min_by(&:expires_on)&.expires_on
    return unless date

    "Expires #{date.strftime('%b %-d')}"
  end

  def ingredient_suppliers_summary(ingredient)
    suppliers = ingredient.suppliers.sort_by(&:name)
    return tag.span("—", class: "text-gray-400") if suppliers.empty?

    primary = suppliers.first
    parts = [link_to(primary.name, admin_inventory_supplier_path(primary), class: "text-blue-600 hover:underline")]
    if suppliers.size > 1
      parts << tag.span(" +#{suppliers.size - 1}", class: "text-gray-500 text-xs")
    end
    safe_join(parts)
  end

  def inventory_tool_link_class(active)
    base = "px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors"
    active ? "#{base} bg-gray-900 text-white border-gray-900" : "#{base} bg-white text-gray-700 border-gray-200 hover:border-gray-300 hover:bg-gray-50"
  end

  def pos_nav_link_class(active)
    base = "px-3 py-1.5 rounded-xl text-sm font-semibold border transition-colors"
    active ? "#{base} bg-gray-900 text-white border-gray-900" : "#{base} bg-white text-gray-600 border-gray-200 hover:bg-gray-50"
  end

  def pos_category_pill_class(active: false)
    base = "pos-category-btn px-4 py-2 rounded-xl text-sm font-semibold border shrink-0 transition-colors"
    active ? "#{base} bg-gray-900 text-white border-gray-900" : "#{base} bg-white text-gray-700 border-gray-200 hover:bg-gray-50"
  end

  POS_INPUT_CLASS = "w-full min-h-11 text-base bg-gray-50 border border-gray-200 rounded-xl px-4 py-2.5 text-gray-900 " \
                    "placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-amber-500/30 " \
                    "focus:border-amber-500 transition-shadow".freeze

  def pos_input_class
    POS_INPUT_CLASS
  end

  def pos_btn_primary_class
    "w-full min-h-11 bg-gray-900 hover:bg-gray-800 text-white py-2.5 rounded-xl text-sm font-semibold transition-colors"
  end

  def pos_btn_accent_class
    "w-full min-h-11 bg-amber-600 hover:bg-amber-700 text-white py-2.5 rounded-xl text-sm font-semibold transition-colors"
  end

  def ingredient_status_badge(ingredient)
    case ingredient.stock_status
    when :out then [t("inventory.stock_status.out"), "bg-red-100 text-red-800 border border-red-200"]
    when :low then [t("inventory.stock_status.low"), "bg-red-100 text-red-800 border border-red-200"]
    when :near then [t("inventory.stock_status.near"), "bg-amber-100 text-amber-900 border border-amber-200"]
    else [t("inventory.stock_status.ok"), "bg-green-100 text-green-800 border border-green-200"]
    end
  end

  def inventory_adjustment_type_label(type)
    t("inventory.adjustment_types.#{type}", default: type.to_s.humanize)
  end

  def purchase_order_status_badge(status)
    label = t("inventory.purchase_orders.statuses.#{status}", default: status.to_s.humanize)
    badge_class = case status.to_s
                  when "draft" then "bg-gray-100 text-gray-800 border-gray-200"
                  when "sent" then "bg-blue-100 text-blue-800 border-blue-200"
                  when "partially_received" then "bg-amber-100 text-amber-900 border-amber-200"
                  when "received" then "bg-green-100 text-green-800 border-green-200"
                  when "cancelled" then "bg-red-100 text-red-800 border-red-200"
                  else "bg-gray-100 text-gray-700 border-gray-200"
                  end
    [label, badge_class]
  end

  def order_type_class(order_type)
    case order_type
    when "delivery" then "bg-blue-100 text-blue-800"
    when "table" then "bg-purple-100 text-purple-800"
    else "bg-amber-100 text-amber-800"
    end
  end

  def order_type_border_class(order_type)
    case order_type
    when "delivery" then "border-blue-200"
    when "table" then "border-purple-200"
    else "border-amber-200"
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

  def stock_take_status_class(status)
    case status
    when "completed" then "bg-green-100 text-green-800"
    when "in_progress" then "bg-amber-100 text-amber-900"
    when "cancelled" then "bg-gray-100 text-gray-700"
    else "bg-gray-100 text-gray-700"
    end
  end

  def stock_take_status_border_class(status)
    case status
    when "completed" then "border-green-200"
    when "in_progress" then "border-amber-200"
    else "border-gray-200"
    end
  end

  def user_role_border_class(role)
    case role
    when "owner" then "border-purple-200"
    when "manager" then "border-blue-200"
    when "cashier" then "border-green-200"
    when "kitchen" then "border-orange-200"
    else "border-gray-200"
    end
  end
end
