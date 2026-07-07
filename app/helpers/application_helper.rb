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

  def accounting_income_category_type(type)
    t("accounting.income_categories.types.#{type}", default: type.to_s.humanize)
  end

  def accounting_treasury_type(type)
    t("accounting.treasuries.types.#{type}", default: type.to_s.humanize)
  end

  def accounting_treasury_transaction_kind(kind)
    t("accounting.treasuries.transaction_kinds.#{kind}", default: kind.to_s.humanize)
  end

  # "≈ 0.26 gallon · 0.99 liter" — shows a base quantity in the ingredient's
  # alternate (purchase) units. Returns nil when there are no alternates.
  def ingredient_alt_unit_hint(ingredient, base_quantity)
    qty = base_quantity.to_d
    return if qty.zero? || ingredient.ingredient_units.none?

    parts = ingredient.ingredient_units.map do |iu|
      converted = number_with_precision(qty / iu.base_units_per_unit, precision: 2, strip_insignificant_zeros: true)
      "#{converted} #{ingredient_unit_label(iu.unit)}"
    end
    "≈ #{parts.join(" · ")}"
  end

  # Returns the vendor invoice URL for an expense linked via VendorInvoicePayment, or nil.
  def expense_source_path(expense)
    return unless expense.source_record_type == "VendorInvoicePayment"
    payment = expense.source_record
    invoice = payment&.vendor_invoice
    admin_inventory_vendor_invoice_path(invoice) if invoice
  end

  # Returns the URL for a transaction's linked source record, or nil if not linkable.
  def treasury_transaction_source_path(transaction)
    case transaction.source_record_type
    when "VendorInvoice"
      admin_inventory_vendor_invoice_path(transaction.source_record_id)
    when "VendorInvoicePayment"
      payment = transaction.source_record
      invoice = payment.vendor_invoice if payment
      admin_inventory_vendor_invoice_path(invoice) if invoice
    when "Expense"
      expense = transaction.source_record
      return unless expense&.source_record_type == "VendorInvoicePayment"
      payment = expense.source_record
      invoice = payment.vendor_invoice if payment
      admin_inventory_vendor_invoice_path(invoice) if invoice
    end
  end

  # A transfer's stored description names the counterparty treasury. When that
  # counterparty is a restricted treasury and the viewer isn't an owner/manager,
  # mask it so the reserve's existence/name isn't leaked on a visible ledger.
  def treasury_transaction_description(transaction, user = current_user)
    transfer = transaction.source_record
    if transaction.kind == "transfer" && transfer.is_a?(TreasuryTransfer) &&
       !(user&.owner? || user&.manager?) &&
       [transfer.from_treasury, transfer.to_treasury].any?(&:restricted?)
      return t("accounting.treasuries.masked_counterparty")
    end

    transaction.description
  end

  # Render a base-unit transfer quantity in the line's (fixed) unit, with the
  # base equivalent as a helper line when the unit differs from the base.
  def transfer_line_quantity(line, base_quantity)
    unit = line.unit.presence || line.ingredient.unit
    primary = "#{number_with_precision(line.in_line_unit(base_quantity), precision: 3, strip_insignificant_zeros: true)} #{ingredient_unit_label(unit)}"
    return primary unless line.unit.present? && line.unit != line.ingredient.unit

    base = "= #{number_with_precision(base_quantity, precision: 3, strip_insignificant_zeros: true)} #{ingredient_unit_label(line.ingredient.unit)}"
    safe_join([primary, tag.span(base, class: "block text-xs text-gray-500")])
  end

  def menu_item_tax_category(category)
    t("admin.menu_items.tax_categories.#{category}", default: category.to_s.humanize)
  end

  def format_tax_rate_percent(tax_rate)
    number_with_precision(tax_rate.rate_percent, precision: 2, strip_insignificant_zeros: true)
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
    scope = controller_path.delete_prefix("admin/").delete_prefix("inventory/").delete_prefix("accounting/")
    t("admin.pages.#{scope}.#{key}", default: controller_name.humanize)
  end

  def locale_button_class(locale)
    base = "px-2.5 py-1.5 rounded-lg transition-colors"
    active = I18n.locale == locale
    active ? "#{base} bg-gray-900 text-white" : "#{base} text-gray-600 hover:bg-gray-100"
  end

  def format_money(cents)
    return Money.new(0).format(locale: I18n.locale) if cents.nil?

    Money.new(cents).format(locale: I18n.locale, symbol: 'ج.م.')
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

  def payment_status_label(status)
    I18n.t("payment.statuses.#{status}", default: status.to_s.humanize)
  end

  def order_event_type_label(event_type)
    I18n.t("order.event_types.#{event_type}", default: event_type.to_s.humanize)
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

    t("inventory.ingredients.expires_on", date: l(date, format: :short))
  end

  def ingredient_unit_label(unit)
    t("inventory.ingredients.units.#{unit}", default: unit.to_s)
  end

  def ingredient_search_options(ingredients)
    ingredients.map { |ingredient| { value: ingredient.id, label: ingredient.name } }.to_json
  end

  def stock_location_option_label(location)
    "#{location.name} (#{t("admin.locations.type_#{location.location_type}")})"
  end

  def ingredient_suppliers_summary(ingredient)
    suppliers = ingredient.suppliers.sort_by(&:name)
    return tag.span(t("accounting.shared.em_dash"), class: "text-gray-400") if suppliers.empty?

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

  def admin_section_tab_class(active)
    base = "inline-flex items-center px-4 py-3 text-sm font-medium border-b-2 -mb-px transition-colors whitespace-nowrap"
    if active
      "#{base} border-amber-600 text-amber-800"
    else
      "#{base} border-transparent text-gray-500 hover:text-gray-900 hover:border-gray-300"
    end
  end

  def pos_nav_link_class(active)
    base = "px-3 py-1.5 rounded-xl text-sm font-semibold border transition-colors"
    active ? "#{base} bg-gray-900 text-white border-gray-900" : "#{base} bg-white text-gray-600 border-gray-200 hover:bg-gray-50"
  end

  def pos_viewport_min_h_class
    "min-h-full"
  end

  def pos_viewport_h_class
    "h-full"
  end

  def pos_category_pill_class(active: false)
    base = "pos-category-btn px-4 py-2 rounded-xl text-sm font-semibold border shrink-0 transition-colors"
    if active
      "#{base} bg-gray-900 text-white border-gray-900 hover:bg-gray-800 hover:text-white"
    else
      "#{base} bg-white text-gray-700 border-gray-200 hover:bg-stone-100 hover:text-gray-800"
    end
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

  def pos_cart_chevron_icon
    tag.svg(
      class: "w-5 h-5 text-stone-500 transition-transform duration-200 group-open:rotate-180",
      fill: "none", stroke: "currentColor", viewBox: "0 0 24 24", "aria-hidden": "true"
    ) do
      tag.path("stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M19 9l-7 7-7-7")
    end
  end

  def pos_cart_expansion_summary_class
    "group/expansion flex items-center justify-between gap-2 px-4 py-3 cursor-pointer list-none " \
      "hover:bg-stone-100/70 transition-colors [&::-webkit-details-marker]:hidden"
  end

  def pos_cart_line_item_class
    "rounded-2xl bg-white p-3 shadow-[0_1px_2px_rgba(0,0,0,0.06)] ring-1 ring-stone-200/50"
  end

  def pos_cart_qty_minus_btn_class
    "w-9 h-9 inline-flex items-center justify-center rounded-full bg-red-100 hover:bg-red-200 " \
      "active:bg-red-300 text-red-800 text-lg font-semibold leading-none transition-colors ring-1 ring-red-200/80"
  end

  def pos_cart_qty_plus_btn_class
    "w-9 h-9 inline-flex items-center justify-center rounded-full bg-emerald-100 hover:bg-emerald-200 " \
      "active:bg-emerald-300 text-emerald-800 text-lg font-semibold leading-none transition-colors ring-1 ring-emerald-200/80"
  end

  def pos_cart_totals_card_class
    "mx-3 mb-2 rounded-2xl bg-white px-4 py-3 shadow-[0_1px_2px_rgba(0,0,0,0.06)] ring-1 ring-stone-200/50 shrink-0"
  end

  def pos_cart_filled_btn_class
    "w-full min-h-11 bg-stone-900 hover:bg-stone-800 active:bg-stone-950 text-white py-3 rounded-full " \
      "text-sm font-medium transition-colors shadow-sm disabled:opacity-40 disabled:pointer-events-none"
  end

  def pos_cart_outlined_btn_class
    "w-full min-h-11 bg-transparent hover:bg-stone-100 active:bg-stone-200 text-stone-800 " \
      "border border-stone-300 py-3 rounded-full text-sm font-medium transition-colors"
  end

  def pos_cart_tonal_btn_class
    "text-sm font-medium text-stone-700 hover:bg-stone-100 active:bg-stone-200 px-3 py-2 " \
      "rounded-full border border-stone-200 transition-colors shrink-0"
  end

  def pos_cart_text_btn_class
    "text-xs font-medium text-red-700 hover:bg-red-50 active:bg-red-100 px-2.5 py-1.5 rounded-full transition-colors"
  end

  def pos_cart_input_class
    "w-full min-h-10 text-sm bg-white border border-stone-300 rounded-xl px-3 py-2 text-stone-900 " \
      "placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-amber-600/20 " \
      "focus:border-amber-600 transition-shadow"
  end

  def pos_cart_chip_class
    "inline-flex items-center rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-medium text-amber-900"
  end


  def vendor_invoice_payment_badge(status)
    label = t("inventory.vendor_invoices.payment_statuses.#{status}", default: status.to_s.humanize)
    badge_class = case status.to_s
                  when "unpaid" then "bg-amber-100 text-amber-900 border-amber-200"
                  when "partially_paid" then "bg-blue-100 text-blue-900 border-blue-200"
                  when "paid" then "bg-green-100 text-green-800 border-green-200"
                  when "void" then "bg-gray-100 text-gray-700 border-gray-200"
                  else "bg-gray-100 text-gray-700 border-gray-200"
                  end
    [label, badge_class]
  end

  def vendor_invoice_balance_due_dollars(invoice)
    cents = invoice.balance_due_cents
    return nil if cents.zero?

    (cents.to_d / 100).round(2)
  end

  def vendor_invoice_line_unit_price_dollars(line)
    cents = line.unit_price_cents.to_i
    return nil if cents.zero? && line.new_record?

    (cents.to_d / 100).round(2)
  end

  def vendor_invoice_line_line_total_dollars(line)
    cents = line.line_total_cents.to_i
    return nil if cents.zero? && line.new_record?

    (cents.to_d / 100).round(2)
  end

  def vendor_invoice_discount_amount_dollars(invoice)
    return nil unless invoice.discount_type == "fixed_amount"
    return nil if invoice.discount_value.blank?

    (invoice.discount_value.to_i / 100.0).round(2)
  end

  def vendor_invoice_discount_label(invoice)
    return nil unless invoice.discounted?

    case invoice.discount_type
    when "percentage"
      t("inventory.vendor_invoices.discount_percentage_label", value: invoice.discount_value)
    when "fixed_amount"
      t("inventory.vendor_invoices.discount_fixed_label", amount: format_money(invoice.discount_cents))
    end
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
    when "accountant" then "bg-teal-100 text-teal-800"
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

  def stock_take_status_label(status)
    t("inventory.stock_takes.statuses.#{status}", default: status.to_s.humanize)
  end

  def stock_take_status_border_class(status)
    case status
    when "completed" then "border-green-200"
    when "in_progress" then "border-amber-200"
    else "border-gray-200"
    end
  end

  def stock_transfer_status_badge(status)
    label = t("inventory.stock_transfers.statuses.#{status}", default: status.to_s.humanize)
    badge_class = case status.to_s
                  when "requested" then "bg-amber-100 text-amber-900 border-amber-200"
                  when "awaiting_receipt" then "bg-blue-100 text-blue-900 border-blue-200"
                  when "partially_received" then "bg-violet-100 text-violet-900 border-violet-200"
                  when "completed" then "bg-green-100 text-green-800 border-green-200"
                  when "cancelled" then "bg-gray-100 text-gray-700 border-gray-200"
                  # legacy
                  when "sent" then "bg-blue-100 text-blue-900 border-blue-200"
                  when "received" then "bg-green-100 text-green-800 border-green-200"
                  else "bg-gray-100 text-gray-700 border-gray-200"
                  end
    [label, badge_class]
  end

  def stock_transfer_shipment_status_badge(status)
    label = t("inventory.stock_transfers.shipment_statuses.#{status}", default: status.to_s.humanize)
    badge_class = case status.to_s
                  when "in_transit" then "bg-blue-100 text-blue-900 border-blue-200"
                  when "received" then "bg-green-100 text-green-800 border-green-200"
                  else "bg-gray-100 text-gray-700 border-gray-200"
                  end
    [label, badge_class]
  end

  def monthly_payroll_sort_link(label, column, sort:, direction:, payroll_month:)
    next_direction = sort == column && direction == "asc" ? "desc" : "asc"
    link_class = "inline-flex items-center gap-1 hover:text-gray-900 transition-colors"
    link_class += sort == column ? " text-gray-900" : " text-gray-500"

    link_to admin_accounting_monthly_payroll_path(
              request.query_parameters.merge(
                payroll_month: payroll_month.strftime("%Y-%m"),
                sort: column,
                direction: next_direction
              )
            ),
            class: link_class do
      safe_join([label, payroll_sort_indicator(sort, direction, column)])
    end
  end

  def staff_index_sort_link(label, column, sort:, direction:)
    next_direction = sort == column && direction == "asc" ? "desc" : "asc"
    link_class = "inline-flex items-center gap-1 hover:text-gray-900 transition-colors"
    link_class += sort == column ? " text-gray-900" : " text-gray-500"

    link_to admin_users_path(request.query_parameters.merge(sort: column, direction: next_direction)),
            class: link_class do
      safe_join([label, payroll_sort_indicator(sort, direction, column)])
    end
  end

  def admin_nav_link_class(active = false)
    base = "block py-2.5 px-2 rounded-lg hover:bg-gray-700 whitespace-nowrap"
    active ? "#{base} bg-gray-700" : base
  end

  def admin_nav_active?(*prefixes)
    prefixes.any? { |prefix| controller_path == prefix || controller_path.start_with?("#{prefix}/") }
  end

  def treasury_index_sort_link(label, column, sort:, direction:)
    next_direction = sort == column && direction == "asc" ? "desc" : "asc"
    link_class = "inline-flex items-center gap-1 hover:text-gray-900 transition-colors"
    link_class += sort == column ? " text-gray-900" : " text-gray-500"

    link_to admin_accounting_treasuries_path(request.query_parameters.merge(sort: column, direction: next_direction)),
            class: link_class do
      safe_join([label, payroll_sort_indicator(sort, direction, column)])
    end
  end

  def user_active_status_class(active)
    active ? "bg-green-100 text-green-800 border-green-200" : "bg-gray-100 text-gray-600 border-gray-200"
  end

  def payroll_adjustment_sort_link(label, column, user:, payroll_month:, payroll_sort:, payroll_direction:, sortable: true)
    return label unless sortable

    next_direction = payroll_sort == column && payroll_direction == "desc" ? "asc" : "desc"
    link_class = "inline-flex items-center gap-1 hover:text-gray-900 transition-colors"
    link_class += payroll_sort == column ? " text-gray-900" : " text-gray-500"

    link_to admin_user_path(
              user,
              payroll_month: payroll_month,
              payroll_sort: column,
              payroll_direction: next_direction
            ),
            class: link_class do
      safe_join([label, payroll_sort_indicator(payroll_sort, payroll_direction, column)].compact)
    end
  end

  def payroll_sort_indicator(current_sort, current_direction, column)
    return unless current_sort == column

    tag.span(current_direction == "asc" ? "↑" : "↓", class: "text-amber-700 not-italic", aria: { hidden: true })
  end

  def payroll_show_url_params(month)
    {
      payroll_month: month,
      payroll_sort: params[:payroll_sort].presence,
      payroll_direction: params[:payroll_direction].presence
    }.compact
  end

  def notification_type_label(type)
    return t("notifications.types.unknown") if type.blank?

    t("notifications.types.#{type}", default: type.titleize)
  end

  def notification_type_class(type)
    case type
    when "inventory" then "bg-amber-100 text-amber-900"
    when "accounting" then "bg-blue-100 text-blue-900"
    else "bg-gray-100 text-gray-700"
    end
  end

  def notification_type_border_class(type)
    case type
    when "inventory" then "border-amber-200"
    when "accounting" then "border-blue-200"
    else "border-gray-200"
    end
  end

  def notification_message_key_label(notification)
    key = notification.params["message_key"] || notification.params[:message_key]
    return t("notifications.keys.unknown") if key.blank?

    t("notifications.keys.#{key}", default: key.humanize)
  end

  def notification_message(notification)
    key = notification.params["message_key"] || notification.params[:message_key]
    legacy = notification.params["message"] || notification.params[:message]
    return legacy if key.blank?

    raw = (notification.params["message_params"] || notification.params[:message_params] || {}).to_h.with_indifferent_access
    if raw[:expires_on].present?
      raw[:date] = l(Date.parse(raw[:expires_on].to_s), format: :short)
    end
    if raw[:session_date].present?
      raw[:date] = l(Date.parse(raw[:session_date].to_s), format: :short)
    end
    if raw[:variance_cents].present?
      raw[:variance] = format_money(raw[:variance_cents].to_i)
    end
    if raw[:unit].present?
      raw[:unit] = ingredient_unit_label(raw[:unit])
    end

    t("notifications.messages.#{key}", **raw.symbolize_keys, default: legacy)
  end

  def user_role_border_class(role)
    case role
    when "owner" then "border-purple-200"
    when "manager" then "border-blue-200"
    when "accountant" then "border-teal-200"
    when "cashier" then "border-green-200"
    when "kitchen" then "border-orange-200"
    else "border-gray-200"
    end
  end
end
