# frozen_string_literal: true

module ApplicationHelper
  # 1-based row number for table lists. Pass +pagy+ so pagination continues across pages.
  def table_row_number(index, pagy: nil)
    (pagy&.offset || 0) + index + 1
  end

  # Alternating row backgrounds — pairs with .table-zebra / .table-zebra-alt in application.css.
  def table_zebra_class
    "table-zebra"
  end

  def html_lang
    I18n.locale.to_s
  end

  # Clickable table header that toggles sort on `key`, preserving all other
  # query params (search, filters). Shows an arrow on the active column.
  # `path` and `base_params` default to the request's own, which is right for a
  # table rendered by a GET. Pass them explicitly where the table also re-renders
  # in response to a POST or PATCH — there the request carries neither.
  def sort_header_link(label, key, sort:, direction:, path: request.path, base_params: request.query_parameters)
    active = sort.to_s == key.to_s
    next_dir = (active && direction == "asc") ? "desc" : "asc"
    indicator = active ? (direction == "asc" ? "↑" : "↓") : ""
    query = base_params.stringify_keys.merge("sort" => key.to_s, "dir" => next_dir)
    link_to "#{path}?#{query.to_query}",
      class: "inline-flex items-center gap-1 hover:text-gray-900 #{'text-gray-900' if active}" do
      safe_join([label, tag.span(indicator, class: "text-amber-600")])
    end
  end

  # Sidebar brand: "<Company> Admin", derived from the current tenant's slug
  # (titleized for display). Falls back to the generic app name off-tenant.
  def admin_brand_name
    brand = Current.company&.slug.to_s.titleize.presence
    return t("app.admin_name") if brand.blank?

    t("app.admin_name_for", brand: brand, default: "#{brand} Admin")
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

  ACCOUNTING_REPORTS_GROUP       = %w[dashboard sales_reports food_costs usage_reports tax_reports budgets financial_statements].freeze
  ACCOUNTING_SETUP_GROUP         = %w[expense_categories income_categories discount_rules audit_log].freeze
  ACCOUNTING_TRANSACTIONS_GROUP  = %w[expenses incomes shift_logs monthly_payroll attendance late_penalties cash_drawer digital_wallet_day_closes business_days].freeze
  ACCOUNTING_LEDGERS_GROUP       = %w[treasuries journal_entries chart_of_accounts fixed_assets partners loans].freeze

  INVENTORY_OPERATIONS_GROUP = %w[vendor_invoices vendor_credit_notes stock_transfers stock_transfer_templates stock_takes manufacturing_templates manufacturing_runs manufacturing_template_lines].freeze
  INVENTORY_SETUP_GROUP      = %w[suppliers ingredients ingredient_categories units unit_conversions].freeze
  INVENTORY_REPORTS_GROUP    = %w[reports].freeze

  # Can this user reshape the inventory catalog (ingredients, vendors,
  # categories, units)? Reading those screens only needs inventory:view, so the
  # add / edit / delete controls are hidden behind this instead.
  def can_manage_inventory_settings?
    current_user&.can?("inventory:settings")
  end

  # Can this user move stock — adjustments, consolidations, voiding an invoice
  # that already landed? The controllers gate these on inventory:manage; the
  # buttons that reach them have to ask the same question, or they render for
  # someone whose click only earns an "unauthorized" flash.
  def can_manage_inventory_stock?
    current_user&.can?("inventory:manage")
  end

  def inventory_in_operations_group?
    INVENTORY_OPERATIONS_GROUP.include?(controller.controller_name)
  end

  def inventory_in_setup_group?
    INVENTORY_SETUP_GROUP.include?(controller.controller_name)
  end

  def inventory_in_reports_group?
    INVENTORY_REPORTS_GROUP.include?(controller.controller_name) &&
      controller.controller_path.start_with?("admin/inventory")
  end

  def accounting_in_reports_group?
    ACCOUNTING_REPORTS_GROUP.include?(controller.controller_name)
  end

  def accounting_in_setup_group?
    ACCOUNTING_SETUP_GROUP.include?(controller.controller_name)
  end

  def accounting_in_transactions_group?
    ACCOUNTING_TRANSACTIONS_GROUP.include?(controller.controller_name)
  end

  def accounting_in_ledgers_group?
    ACCOUNTING_LEDGERS_GROUP.include?(controller.controller_name)
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

  # "Sep 5 – Sep 11, 2026". Names both ends of the week: a Saturday→Friday week
  # (see config.beginning_of_week) reads wrong to anyone expecting a Monday
  # start unless the closing day is spelled out. Only the year is dropped from
  # the opening day — a bare day number reads as a price next to the totals.
  def treasury_week_label(week_start, week_end)
    "#{l(week_start, format: :day_month)} – #{l(week_end, format: :long)}"
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

  # A name a person can read for whatever a record came from.
  #
  # Views used to fall back to `record.to_s`, which on an ActiveRecord object is
  # its Ruby inspect — "#<VendorInvoicePayment:0x000077818411e4c8>" turned up on
  # the expense page in production. Nothing is worse than that, so anything
  # unrecognised falls back to the model name and its id instead.
  def source_record_label(type, id, record = nil)
    case type
    when "VendorInvoice"
      record&.invoice_number ? "#{t('activerecord.models.vendor_invoice', count: 1)} #{record.invoice_number}" : generic_source_label(type, id)
    when "VendorInvoicePayment"
      invoice = record&.vendor_invoice
      invoice ? "#{t('activerecord.models.vendor_invoice', count: 1)} #{invoice.invoice_number} — #{t('accounting.journal_entries.payment_label')}" : generic_source_label(type, id)
    when "Voucher"
      record&.number || generic_source_label(type, id)
    when "Order"
      record&.order_number ? "#{t('activerecord.models.order', count: 1)} ##{record.order_number}" : generic_source_label(type, id)
    when "Expense", "Income"
      record&.description.presence || generic_source_label(type, id)
    when "Location"
      record&.name.presence || generic_source_label(type, id)
    else
      generic_source_label(type, id)
    end
  end

  # Never an object inspect, and never a bare uuid on its own line.
  def generic_source_label(type, id)
    "#{type&.underscore&.humanize || t("shared.unknown", default: "Unknown")} ##{id.to_s.first(8)}"
  end

  # Returns the vendor invoice URL for an expense linked via VendorInvoicePayment, or nil.
  def expense_source_path(expense)
    return unless expense.source_record_type == "VendorInvoicePayment"
    payment = expense.source_record
    invoice = payment&.vendor_invoice
    admin_inventory_vendor_invoice_path(invoice) if invoice
  end

  # Returns the URL for a JE's source record, or nil if the source type has no show page.
  def journal_entry_source_path(je)
    case je.source_record_type
    when "VendorInvoice"
      admin_inventory_vendor_invoice_path(je.source_record_id)
    when "Voucher"
      admin_accounting_voucher_path(je.source_record_id)
    when "VendorInvoicePayment"
      payment = je.source_record
      invoice = payment&.vendor_invoice
      admin_inventory_vendor_invoice_path(invoice) if invoice
    when "Order"
      admin_order_path(je.source_record_id)
    when "Expense"
      admin_accounting_expense_path(je.source_record_id)
    when "Income"
      admin_accounting_income_path(je.source_record_id)
    end
  end

  # Returns a human-readable label for the JE's source record.
  def journal_entry_source_label(je)
    case je.source_record_type
    when "VendorInvoice"
      record = je.source_record
      record ? "#{t('activerecord.models.vendor_invoice', count: 1)} #{record.invoice_number}" : fallback_je_source_label(je)
    when "Voucher"
      record = je.source_record
      record ? record.number : fallback_je_source_label(je)
    when "VendorInvoicePayment"
      payment = je.source_record
      invoice = payment&.vendor_invoice
      invoice ? "#{t('activerecord.models.vendor_invoice', count: 1)} #{invoice.invoice_number} — #{t('accounting.journal_entries.payment_label')}" : fallback_je_source_label(je)
    when "Order"
      record = je.source_record
      record ? "#{t('activerecord.models.order', count: 1)} ##{record.order_number}" : fallback_je_source_label(je)
    when "Expense"
      record = je.source_record
      record&.description.presence || t("activerecord.models.expense", count: 1)
    when "Income"
      record = je.source_record
      record&.description.presence || t("activerecord.models.income", count: 1)
    else
      fallback_je_source_label(je)
    end
  end

  # Returns the URL for a transaction's linked source record, or nil if not linkable.
  def treasury_transaction_source_path(transaction)
    case transaction.source_record_type
    when "VendorInvoice"
      admin_inventory_vendor_invoice_path(transaction.source_record_id)
    when "Voucher"
      admin_accounting_voucher_path(transaction.source_record_id)
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

  # Just the numeric amount of a base quantity expressed in the line's unit.
  # Used where the unit is shown in its own column.
  def transfer_line_amount(line, base_quantity)
    number_with_precision(line.in_line_unit(base_quantity), precision: 3, strip_insignificant_zeros: true)
  end

  # The line's (fixed) unit label — for a dedicated Unit column.
  def transfer_line_unit_label(line)
    ingredient_unit_label(line.unit.presence || line.ingredient.unit)
  end

  # Groups transfer / shipment line records by ingredient category (category
  # position, then name). Records without a category land in "Uncategorized".
  # Each record must respond to `ingredient`.
  def group_records_by_ingredient_category(records)
    Array(records).reject { |r| r.respond_to?(:marked_for_destruction?) && r.marked_for_destruction? }
      .group_by { |r| r.ingredient&.ingredient_category }
      .sort_by { |cat, _| IngredientCategory.grouping_sort_key(cat) }
      .map do |cat, items|
        sorted = items.sort_by do |r|
          position = r.respond_to?(:position) ? r.position : r.try(:stock_transfer_line)&.position
          [position.to_i, r.ingredient&.name.to_s.downcase]
        end
        [cat&.name.presence || t("inventory.stock_transfers.uncategorized"), sorted]
      end
  end

  # Like `group_records_by_ingredient_category`, but keeps each category's line
  # order as given (e.g. after a user-chosen sort on the template show page).
  def group_preserving_line_order_by_ingredient_category(records)
    Array(records).reject { |r| r.respond_to?(:marked_for_destruction?) && r.marked_for_destruction? }
      .group_by { |r| r.ingredient&.ingredient_category }
      .sort_by { |cat, _| IngredientCategory.grouping_sort_key(cat) }
      .map do |cat, items|
        [cat&.name.presence || t("inventory.stock_transfers.uncategorized"), items]
      end
  end

  def duplicate_ingredient_ids(lines)
    Array(lines).group_by(&:ingredient_id).filter_map { |id, group| id if id.present? && group.size > 1 }
  end

  def template_line_sort_key(line, sort)
    case sort.to_s
    when "order_limit"
      line.default_quantity.to_d
    when "ingredient"
      line.ingredient.name.to_s.downcase
    else
      [line.position.to_i, line.created_at.to_i]
    end
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
    bt_t("admin.pages.#{scope}.#{key}", default: controller_name.humanize)
  end

  # Business-type-aware relabeling (step 5). A distribution company sees "Product"
  # where a restaurant sees "Ingredient", etc. Only a handful of high-visibility
  # labels are remapped; everything else falls through to the normal translation.
  BUSINESS_TERM_OVERRIDES = {
    "distribution" => {
      "inventory.tools.ingredients"              => "glossary.distribution.products",
      "inventory.tools.ingredient_categories"    => "glossary.distribution.product_categories",
      "admin.pages.ingredients.title"            => "glossary.distribution.products",
      "admin.pages.ingredient_categories.title"  => "glossary.distribution.product_categories",
      "inventory.ingredients.index.new_button"   => "glossary.distribution.new_product",
      "inventory.ingredients.index.description"  => "glossary.distribution.products_description"
    }
  }.freeze

  def bt_t(key, **opts)
    override = BUSINESS_TERM_OVERRIDES.dig(Current.company&.business_type.to_s, key.to_s)
    override ? t(override, **opts) : t(key, **opts)
  end

  def locale_button_class(locale)
    base = "px-2.5 py-1.5 rounded-lg transition-colors"
    active = I18n.locale == locale
    active ? "#{base} bg-gray-900 text-white" : "#{base} text-gray-600 hover:bg-gray-100"
  end

  # Money.default_currency is :usd, so every render has to override the symbol.
  # Kept in one place so formatted amounts and chart axis labels can't disagree.
  MONEY_SYMBOL = "ج.م."

  def money_symbol
    MONEY_SYMBOL
  end

  # App-wide rule: views show bare numbers. The currency is a constant for the
  # whole system, so repeating "ج.م." on every cell is noise that costs column
  # width and makes tables harder to scan. Use this everywhere.
  def format_amount(cents)
    Money.new(cents || 0).format(locale: I18n.locale, symbol: false)
  end

  # Only for the few places the currency has to be explicit: printed/exported
  # documents, a lone figure with no column header to name it, and anywhere the
  # reader might not be looking at a page that already establishes the currency.
  def format_money(cents)
    Money.new(cents || 0).format(locale: I18n.locale, symbol: MONEY_SYMBOL)
  end

  # A small "i" icon that reveals explanatory text next to a label — on hover
  # where the device supports it, on tap where it doesn't (see tooltip_controller.js).
  # For a short line of methodology text that would otherwise need its own
  # always-visible panel, e.g. beside a stat tile's title.
  def info_tooltip_icon(text)
    tag.span class: "relative inline-flex align-middle ms-1", data: { controller: "tooltip" } do
      button = tag.button type: "button",
        class: "text-gray-400 hover:text-gray-600 focus:outline-none focus:text-gray-600",
        aria: { label: t("shared.more_info") },
        data: {
          tooltip_target: "trigger",
          action: "mouseenter->tooltip#onMouseEnter mouseleave->tooltip#onMouseLeave " \
                   "focus->tooltip#onFocus blur->tooltip#onBlur click->tooltip#toggle"
        } do
        tag.svg class: "w-3.5 h-3.5", fill: "none", viewBox: "0 0 24 24", stroke: "currentColor", "stroke-width": 2 do
          tag.path "stroke-linecap": "round", "stroke-linejoin": "round",
            d: "M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 " \
               "9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z"
        end
      end
      # A <span>, not a <div>: this icon sits inside a <p> title, and a <div>
      # there would implicitly close the <p> per the HTML5 parsing rules,
      # hoisting the panel out of this wrapper and breaking the target lookup.
      panel = tag.span text,
        role: "tooltip",
        class: "hidden absolute z-20 top-full mt-2 start-0 w-64 max-w-[80vw] rounded-xl border " \
               "border-gray-200 bg-white p-3 text-xs leading-relaxed text-gray-600 shadow-lg normal-case font-normal",
        data: { tooltip_target: "panel" }
      button + panel
    end
  end

  AUDIT_HISTORY_HIDDEN_FIELDS = %w[
    company_id source_record_id source_record_type ingredient_id
  ].freeze

  AUDIT_HISTORY_ASSOCIATIONS = {
    "expense_category_id" => [ExpenseCategory, :name],
    "income_category_id" => [IncomeCategory, :name],
    "treasury_id" => [Treasury, :name],
    "user_id" => [User, :name],
    "role_id" => [Role, :name],
    "assigned_treasury_id" => [Treasury, :name],
    "category_id" => [Category, :name],
    "ingredient_category_id" => [IngredientCategory, :name],
    "unit_id" => [Unit, :name],
    "attendance_status_id" => [AttendanceStatus, :label_with_symbol],
    "location_id" => [Location, :name],
    "assigned_user_id" => [User, :name],
    "created_by_id" => [User, :name],
    "customer_id" => [Customer, :name]
  }.freeze

  def audit_history_rows(audit)
    changes = audit.audited_changes
    return [] if changes.blank?

    changes.filter_map do |field, value|
      field = field.to_s
      next if AUDIT_HISTORY_HIDDEN_FIELDS.include?(field)

      label = t("accounting.audit_history.fields.#{field}", default: field.humanize)
      if audit.action.to_s == "update" && value.is_a?(Array) && value.size == 2
        {
          label: label,
          kind: :update,
          from: format_audit_history_value(field, value[0]),
          to: format_audit_history_value(field, value[1])
        }
      else
        {
          label: label,
          kind: :set,
          value: format_audit_history_value(field, value.is_a?(Array) ? value.last : value)
        }
      end
    end
  end

  def format_audit_history_value(field, value)
    return t("accounting.shared.em_dash") if value.nil? || value == ""

    if AUDIT_HISTORY_ASSOCIATIONS.key?(field)
      klass, attr = AUDIT_HISTORY_ASSOCIATIONS.fetch(field)
      record = klass.unscoped.find_by(id: value)
      return record ? record.public_send(attr) : t("accounting.shared.em_dash")
    end

    case field
    when /_cents\z/
      format_money(value.to_i)
    when /\A.*_date\z/, "reversed_at"
      begin
        time = value.is_a?(String) ? Time.zone.parse(value) : value
        time ? l(time.to_date, format: :default) : t("accounting.shared.em_dash")
      rescue ArgumentError, TypeError
        value.to_s
      end
    else
      case value
      when true then t("accounting.audit_history.boolean.true")
      when false then t("accounting.audit_history.boolean.false")
      else
        human = t("accounting.audit_history.values.#{field}.#{value}", default: nil)
        human.presence || value.to_s
      end
    end
  end

  # The operating day currently in progress (day boundary shifted to the
  # per-company business-day cutoff hour). Use instead of Date.current in views
  # that mean "today's business day".
  def business_today
    BusinessDay.today
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

  def order_payment_methods_label(order)
    methods = order.payments
      .select { |payment| payment.status == "completed" }
      .map(&:payment_method)
      .uniq
    return tag.span(t("accounting.shared.em_dash"), class: "text-gray-400") if methods.empty?

    methods.map { |method| payment_method_label(method) }.join(", ")
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

  def ingredient_stock_row_class(ingredient_or_status)
    status = ingredient_or_status.respond_to?(:stock_status) ? ingredient_or_status.stock_status : ingredient_or_status
    case status
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
    t("inventory.unit_labels.#{unit}", default: unit.to_s)
  end

  def format_purchase_request_qty(quantity, whole_units: false)
    precision = whole_units ? 0 : 3
    number_with_precision(quantity, precision: precision, strip_insignificant_zeros: true)
  end

  # Render a stock adjustment's delta in the unit it was entered (system
  # adjustments are base-unit), with a base-unit helper line when they differ.
  # Returns the Rails path to the source document that triggered this adjustment,
  # or nil when no linkable source exists (manual, waste, cycle count, etc.).
  def stock_adjustment_source_path(adjustment)
    case adjustment.adjustment_type
    when "vendor_invoice", "delivery"
      invoice = adjustment.stock_batch&.vendor_invoice_line&.vendor_invoice
      admin_inventory_vendor_invoice_path(invoice) if invoice
    when "transfer_in", "transfer_out"
      transfer = adjustment.stock_transfer
      admin_inventory_stock_transfer_path(transfer) if transfer
    end
  end

  def stock_adjustment_quantity(adjustment)
    ingredient = adjustment.ingredient
    base = adjustment.quantity_delta.to_d
    sign = base.positive? ? "+" : ""
    unit = adjustment.unit.presence || ingredient.unit
    begin
      shown = ingredient.from_base(base, adjustment.unit)
    rescue ArgumentError
      # Legacy/orphaned unit — fall back to displaying the base-unit quantity
      # instead of crashing the adjustments list.
      unit = ingredient.unit
      shown = base
    end
    primary = "#{sign}#{number_with_precision(shown, precision: 3, strip_insignificant_zeros: true)} #{ingredient_unit_label(unit)}"
    return primary unless adjustment.unit.present? && adjustment.unit != ingredient.unit && unit != ingredient.unit

    helper = "= #{sign}#{number_with_precision(base, precision: 3, strip_insignificant_zeros: true)} #{ingredient_unit_label(ingredient.unit)}"
    safe_join([primary, tag.span(helper, class: "block text-xs text-gray-500 font-normal")])
  end

  # [label, id] options for the current company's active units.
  def company_unit_options
    Current.company.units.active.ordered.map { |u| [ingredient_unit_label(u.name), u.id] }
  end

  def ingredient_search_options(ingredients, vendor_aliases: false)
    ingredients.map do |ingredient|
      option = { value: ingredient.id, label: ingredient.name }
      if vendor_aliases
        names = ingredient.supplier_ingredients
                          .flat_map { |si| [si.vendor_product_name, si.vendor_sku] }
                          .compact_blank.uniq
        if names.any?
          option[:keywords] = names.join(" ") # extra searchable text, not shown as the label
          option[:aliases] = names            # shown as a muted sub-line in the dropdown
        end
      end
      option
    end.to_json
  end

  # Options for a searchable customer picker. Selling to walk-in customers through
  # the invoice form puts the whole customer base in one control, so it has to be
  # searchable by phone and old-system code as well as by name.
  def customer_search_options(customers)
    customers.map do |customer|
      option = { value: customer.id, label: customer.display_name }
      hints = [customer.phone, customer.phone_secondary, customer.legacy_code].compact_blank
      if hints.any?
        option[:keywords] = hints.join(" ")
        option[:aliases] = hints
      end
      option
    end.to_json
  end

  def shipping_company_search_options(shipping_companies)
    shipping_companies.map { |sc| { value: sc.id, label: sc.name } }.to_json
  end

  # ingredient_id => { id, name, position } for client-side category grouping on transfer forms.
  def ingredient_categories_json(ingredients)
    ingredients.to_h do |ingredient|
      cat = ingredient.ingredient_category
      [
        ingredient.id,
        {
          id: cat&.id,
          name: cat&.name.presence || t("inventory.stock_transfers.uncategorized"),
          position: cat ? cat.position.to_i : 999_999
        }
      ]
    end.to_json
  end

  # Flat searchable options from AccountListService's grouped [[label, value], ...] lists.
  def journal_entry_account_search_options(account_groups)
    account_groups.flat_map { |_group, options| options }.map do |label, value|
      { value: value, label: label }
    end.to_json
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

  # Count pill rendered inside an admin section tab, so the queue size is
  # visible without clicking through.
  def admin_tab_count(count, active: false)
    tone = active ? "bg-amber-100 text-amber-900" : "bg-gray-100 text-gray-600"
    tag.span(count.to_i, class: "ms-2 text-xs font-semibold tabular-nums px-1.5 py-0.5 rounded-md #{tone}")
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
    when "completing" then "bg-blue-100 text-blue-900"
    when "failed" then "bg-red-100 text-red-800"
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
    when "completing" then "border-blue-200"
    when "failed" then "border-red-200"
    else "border-gray-200"
    end
  end

  def stock_transfer_status_badge(status)
    label = t("inventory.stock_transfers.statuses.#{status}", default: status.to_s.humanize)
    badge_class = case status.to_s
                  # Dashed border reads as "not final yet".
                  when "draft" then "bg-white text-gray-500 border-gray-300 border-dashed"
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
                  when "voided" then "bg-red-50 text-red-800 border-red-200"
                  # Distinct from voided: stock really moved and was moved back,
                  # which is a different thing from a load that never left.
                  when "reverted" then "bg-purple-50 text-purple-800 border-purple-200"
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

  # Literal class strings (not interpolated) so Tailwind's purge keeps them.
  ATTENDANCE_COLOR_CLASSES = {
    "emerald" => "bg-emerald-100 text-emerald-800",
    "teal"    => "bg-teal-100 text-teal-800",
    "blue"    => "bg-blue-100 text-blue-800",
    "indigo"  => "bg-indigo-100 text-indigo-800",
    "amber"   => "bg-amber-100 text-amber-800",
    "red"     => "bg-red-100 text-red-800",
    "gray"    => "bg-gray-100 text-gray-700"
  }.freeze

  def attendance_color_classes(color)
    ATTENDANCE_COLOR_CLASSES[color.to_s] || ATTENDANCE_COLOR_CLASSES["gray"]
  end

  # status.label is the raw string stored on the row (seeded in English). Translate
  # it for the known seeded codes; a company-renamed or future custom status falls
  # back to whatever was typed in, since that text can't be machine-translated.
  def attendance_status_label(status)
    return "" if status.nil?

    t("accounting.attendance_statuses.#{status.code}", default: status.label)
  end

  # A status's letter code in its grid color, plus its label — e.g. for the
  # attendance change-history popover, so "P → A" reads the same letters the
  # grid itself uses, not just the long label.
  def attendance_status_chip(status)
    return tag.span(t("accounting.shared.em_dash"), class: "text-gray-400") if status.nil?

    tag.span(class: "inline-flex items-center gap-1.5") do
      concat tag.span(status.symbol, class: "inline-flex items-center justify-center w-5 h-5 rounded text-[10px] font-bold shrink-0 #{attendance_color_classes(status.color)}")
      concat attendance_status_label(status)
    end
  end

  def admin_nav_link_class(active = false)
    base = "flex items-center gap-3 py-2.5 px-2 rounded-lg hover:bg-gray-700 whitespace-nowrap"
    active ? "#{base} bg-gray-700" : base
  end

  # Simple, self-authored line icons for the admin sidebar. Kept intentionally
  # geometric so they render crisply at 20px and can't break like copy-pasted
  # long icon paths. Inherit color/size from the parent link.
  ADMIN_NAV_ICON_PATHS = {
    dashboard: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    orders: '<path d="M6 3h9l4 4v13a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M14 3v4h4"/><path d="M8 12h8M8 16h5"/>',
    menu: '<path d="M4 5a2 2 0 0 1 2-2h5v16H6a2 2 0 0 0-2 2V5z"/><path d="M20 5a2 2 0 0 0-2-2h-5v16h5a2 2 0 0 1 2 2V5z"/>',
    customers: '<circle cx="8.5" cy="8" r="3"/><circle cx="16" cy="9" r="2.3"/><path d="M3 20a5.5 5.5 0 0 1 11 0"/><path d="M15 14.6a5 5 0 0 1 6 5.4"/>',
    inventory: '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3z"/><path d="M4 7.5l8 4.5 8-4.5"/><path d="M12 12v9"/>',
    accounting: '<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="6" width="8" height="3" rx="0.5"/><path d="M8.5 13h0M12 13h0M15.5 13h0M8.5 16.5h0M12 16.5h0M15.5 16.5h0"/>',
    settings: '<path d="M4 6h8M16 6h4"/><circle cx="14" cy="6" r="2"/><path d="M4 12h4M12 12h8"/><circle cx="10" cy="12" r="2"/><path d="M4 18h8M16 18h4"/><circle cx="14" cy="18" r="2"/>',
    pos: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
    kitchen: '<path d="M4 9h16"/><path d="M6 9v7a3 3 0 0 0 3 3h6a3 3 0 0 0 3-3V9"/><path d="M2 12h2M20 12h2"/><path d="M11 5c-.5.7-.5 1.3 0 2M14 5c-.5.7-.5 1.3 0 2"/>',
    production: '<path d="M3 21h18"/><path d="M5 21V11l5 3V11l5 3V8l4 2v11"/><path d="M8 21v-3M12 21v-3M16 21v-3"/>',
    ledgers: '<path d="M5 4h13a1 1 0 0 1 1 1v15a1 1 0 0 1-1 1H7a2 2 0 0 1-2-2V4z"/><path d="M5 18.5A1.5 1.5 0 0 1 6.5 17H19"/><path d="M9 8h6M9 11h4"/>',
    transactions: '<path d="M7 5v12M7 5L4 8M7 5l3 3"/><path d="M17 19V7M17 19l3-3M17 19l-3-3"/>',
    reports: '<path d="M4 20h16"/><rect x="6" y="12" width="3" height="5"/><rect x="10.5" y="8" width="3" height="9"/><rect x="15" y="14" width="3" height="3"/>',
    gear: '<path d="M10.343 3.94c.09-.542.56-.94 1.11-.94h1.093c.55 0 1.02.398 1.11.94l.149.894c.07.424.384.764.78.93.398.164.855.142 1.205-.108l.737-.527a1.125 1.125 0 0 1 1.45.12l.773.774c.39.389.44 1.002.12 1.45l-.527.737c-.25.35-.272.806-.107 1.204.165.397.505.71.93.78l.893.15c.543.09.94.56.94 1.11v1.093c0 .55-.397 1.02-.94 1.11l-.893.149c-.425.07-.765.383-.93.78-.165.398-.143.854.107 1.204l.527.738c.32.447.269 1.06-.12 1.45l-.774.773a1.125 1.125 0 0 1-1.449.12l-.738-.527c-.35-.25-.806-.272-1.203-.107-.397.165-.71.505-.781.929l-.149.894c-.09.542-.56.94-1.11.94h-1.094c-.55 0-1.019-.398-1.11-.94l-.148-.894c-.071-.424-.384-.764-.781-.93-.398-.164-.854-.142-1.204.108l-.738.527c-.447.32-1.06.269-1.45-.12l-.773-.774a1.125 1.125 0 0 1-.12-1.45l.527-.737c.25-.35.273-.806.108-1.204-.165-.397-.505-.71-.93-.78l-.894-.15c-.542-.09-.94-.56-.94-1.11v-1.094c0-.55.398-1.019.94-1.11l.894-.148c.424-.071.765-.384.93-.781.165-.398.143-.854-.108-1.204l-.526-.738a1.125 1.125 0 0 1 .12-1.45l.773-.773a1.125 1.125 0 0 1 1.45-.12l.737.527c.35.25.807.272 1.204.107.397-.165.71-.505.78-.929l.15-.894z"/><path d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0z"/>',
    operations: '<rect x="6" y="4" width="12" height="17" rx="2"/><path d="M9 4V3.5A.5.5 0 0 1 9.5 3h5a.5.5 0 0 1 .5.5V4"/><path d="M9 10h6M9 13.5h6M9 17h4"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>'
  }.freeze

  def admin_nav_icon(name, css: "w-5 h-5 shrink-0")
    inner = ADMIN_NAV_ICON_PATHS[name.to_sym]
    return "".html_safe if inner.nil?

    content_tag(:svg, raw(inner),
      class: css, viewBox: "0 0 24 24", fill: "none",
      stroke: "currentColor", "stroke-width": "1.7",
      "stroke-linecap": "round", "stroke-linejoin": "round",
      "aria-hidden": "true")
  end

  def admin_nav_active?(*prefixes)
    prefixes.any? { |prefix| controller_path == prefix || controller_path.start_with?("#{prefix}/") }
  end

  # Controllers surfaced under the Settings section (some live in other
  # namespaces but are presented as Settings tabs).
  SETTINGS_SECTION_CONTROLLERS = %w[
    admin/settings admin/users admin/locations admin/printers admin/workstations admin/roles
    admin/accounting/integrations admin/accounting/payment_method_treasuries
  ].freeze

  def in_settings_section?
    admin_nav_active?(*SETTINGS_SECTION_CONTROLLERS)
  end

  # ── Permission-driven accounting nav ─────────────────────────────
  # Only tabs the user can? see are rendered; group/section links land on the
  # first accessible tab, so clicking never 403s.
  # A tab is shown only when the user has the permission AND the module it belongs
  # to is enabled for this company's business profile (tabs with no :feature are
  # always feature-enabled).
  def tab_feature_enabled?(tab)
    feature = tab[:feature]
    feature.nil? || Current.company&.feature_enabled?(feature)
  end

  def accounting_visible_tabs(group)
    group[:tabs].select { |tab| tab_feature_enabled?(tab) && current_user.can?(tab[:permission]) }
  end

  def accounting_visible_groups
    AccountingNav::GROUPS.select { |group| accounting_visible_tabs(group).any? }
  end

  def accounting_sidebar_groups
    accounting_visible_groups.map { |group| group.merge(tabs: accounting_visible_tabs(group)) }
  end

  # Sidebar list: every non-report tab, flattened — Ledgers, Transactions and
  # Setup no longer get their own sub-headers now that Reports has its own
  # dedicated hub page. The dashboard tab lives in the :reports group and
  # moves to the hub with the rest of them.
  def accounting_sidebar_items
    accounting_sidebar_groups.reject { |g| g[:key] == :reports }.flat_map { |g| g[:tabs] }
  end

  def accounting_report_items
    group = accounting_sidebar_groups.find { |g| g[:key] == :reports }
    group ? group[:tabs] : []
  end

  def accounting_any_access?
    accounting_sidebar_items.any?
  end

  def accounting_tab_active?(tab)
    return false unless controller.controller_name == tab[:controller]

    tab[:action].nil? || params[:action] == tab[:action]
  end

  # ── Permission-driven inventory nav ──────────────────────────────
  def inventory_visible_tabs(group)
    group[:tabs].select { |tab| tab_feature_enabled?(tab) && current_user.can?(tab[:permission]) }
  end

  def inventory_visible_groups
    InventoryNav::GROUPS.select { |group| inventory_visible_tabs(group).any? }
  end

  def inventory_sidebar_groups
    inventory_visible_groups.map { |group| group.merge(tabs: inventory_visible_tabs(group)) }
  end

  # Sidebar list: every non-report tab, flattened — Operations and Setup no
  # longer get their own sub-headers now that Reports has its own dedicated
  # hub page.
  def inventory_sidebar_items
    inventory_sidebar_groups.reject { |g| g[:key] == :reports }.flat_map { |g| g[:tabs] }
  end

  def inventory_report_items
    group = inventory_sidebar_groups.find { |g| g[:key] == :reports }
    group ? group[:tabs] : []
  end

  def inventory_any_access?
    inventory_sidebar_items.any?
  end

  def inventory_tab_active?(tab)
    return false unless controller.controller_path.start_with?("admin/inventory")

    inventory_tab_matches?(tab)
  end

  def inventory_tab_matches?(tab)
    names = Array(tab[:controllers].presence || tab[:controller])
    return false unless names.include?(controller.controller_name)

    tab[:action].nil? || params[:action] == tab[:action]
  end

  # ── Permission-driven sales nav ───────────────────────────────────
  # No natural sub-groups (unlike Inventory/Accounting) — one flat list,
  # same as Settings. Sales reports and Leads reports are dedicated pages
  # reachable only from the Reports hub (see sales_report_items above), not
  # listed here.
  def sales_sidebar_items
    items = []

    if current_user.can?("customers:manage") && Current.company&.feature_enabled?(:ar_credit_sales)
      items << { controller: "customer_invoices", label: "sales.nav.invoices", path: :admin_sales_customer_invoices_path }
      items << { controller: "customer_statements", label: "sales.nav.statements", path: :admin_sales_customer_statements_path }
      items << { controller: "credit_notes", label: "sales.nav.credit_notes", path: :admin_sales_credit_notes_path }
      items << { controller: "price_tiers", label: "sales.nav.price_tiers", path: :admin_sales_price_tiers_path }
      items << { controller: "shipping_companies", label: "sales.nav.shipping_companies", path: :admin_sales_shipping_companies_path }
      items << { controller: "payment_methods", label: "sales.nav.payment_methods", path: :admin_sales_payment_methods_path }
    end

    if current_user.can?("sales:confirm_payments") && Current.company&.feature_enabled?(:ar_credit_sales)
      items << { controller: "payment_approvals", label: "sales.nav.payment_approvals", path: :admin_sales_payment_approvals_path }
    end

    if Current.company&.feature_enabled?(:leads) && current_user.can?("leads:view")
      items << { controller: "leads", label: "sales.nav.leads", path: :admin_sales_leads_path }
    end

    items
  end

  def sales_any_access?
    sales_sidebar_items.any?
  end

  # Not its own controller — the approval queue is the invoices index, filtered.
  def admin_sales_payment_approvals_path
    admin_sales_customer_invoices_path(status: "pending_payment_confirmation")
  end

  def sales_tab_active?(tab)
    return false unless controller.controller_path.start_with?("admin/sales")

    controller.controller_name == tab[:controller]
  end

  # ── Reports hub — one page for every report across modules ───────
  # Inventory/Accounting expose their own report tabs (see *_report_items
  # above, sourced from the same Nav modules the sidebar uses); Sales
  # (distribution) only has these pages, defined inline here since it isn't
  # modeled as a Nav module like the other two. Each entry is gated on its own
  # feature+permission — ar_credit_sales and leads are independent (a company
  # can have a lead pipeline without full AR credit sales), so this builds the
  # list item-by-item rather than all-or-nothing.
  def sales_report_items
    items = []

    if Current.company&.feature_enabled?(:ar_credit_sales) && current_user.can?("customers:manage")
      items << { label: t("sales.nav.reports"), path: admin_sales_reports_path, description: t("sales.reports.description") }
    end

    if Current.company&.feature_enabled?(:leads) && current_user.can?("leads:reports")
      items << { label: t("sales.nav.lead_reports"), path: admin_sales_lead_reports_path,
                 description: t("sales.lead_reports.description") }
    end

    items
  end

  def reports_hub_sections
    sections = []

    inv = inventory_report_items
    if inv.any?
      sections << { key: :inventory, label: t("nav.inventory"), icon: :inventory,
                     items: inv.map { |tab| { label: bt_t(tab[:label]), path: public_send(tab[:path]),
                                               description: tab[:description] && t(tab[:description]) } } }
    end

    acc = accounting_report_items
    if acc.any?
      sections << { key: :accounting, label: t("nav.accounting"), icon: :accounting,
                     items: acc.map { |tab| { label: t(tab[:label]), path: public_send(tab[:path]),
                                               description: tab[:description] && t(tab[:description]) } } }
    end

    sales = sales_report_items
    sections << { key: :sales, label: t("nav.sales"), icon: :orders, items: sales } if sales.any?

    sections
  end

  def reports_any_access?
    reports_hub_sections.any?
  end

  # ── Settings nav — flat, no natural sub-groups ───────────────────
  # Single source of truth for both the sidebar accordion and the command
  # palette; mirrors the exact visibility rules the old in-page settings nav
  # used (role-based, not permission-key based, unlike Inventory/Accounting).
  def settings_nav_items
    items = []
    if current_user.owner? || current_user.accountant?
      items << { label: t("settings.nav.general"), path: admin_settings_path, controller: "settings" }
      items << { label: t("nav.staff"), path: admin_users_path, controller: "users" }
    end
    if current_user.can_access_admin?
      items << { label: t("nav.locations"), path: admin_locations_path, controller: "locations" }
      items << { label: t("nav.printers"), path: admin_printers_path, controller: "printers" }
      items << { label: t("nav.workstations"), path: admin_workstations_path, controller: "workstations" }
    end
    if current_user.owner?
      items << { label: t("settings.nav.roles"), path: admin_roles_path, controller: "roles" }
      items << { label: t("settings.nav.integrations"), path: admin_accounting_integrations_path, controller: "integrations" }
      items << { label: t("settings.nav.online_payments"), path: admin_accounting_payment_method_treasuries_path, controller: "payment_method_treasuries" }
    end
    items
  end

  def settings_nav_item_active?(item)
    controller.controller_name == item[:controller]
  end

  def settings_any_access?
    settings_nav_items.any?
  end

  # ── Command palette (Cmd/Ctrl+K) ─────────────────────────────────
  # Flat, permission-gated list of every destination the sidebar can reach,
  # regardless of how many accordion levels it sits behind — lets a user jump
  # straight to "Ingredients" without expanding Inventory then its Setup group.
  def command_palette_items
    items = []

    if current_user.can?("dashboard:view")
      items << { label: t("nav.dashboard"), path: admin_root_path, group: t("nav.dashboard") }
    end

    menu_selling = tab_feature_enabled?(feature: :menu)
    if menu_selling && current_user.can?("orders:view")
      items << { label: t("nav.orders"), path: admin_orders_path, group: t("nav.groups.sell_serve") }
    end
    if menu_selling && current_user.can?("menu:manage")
      items << { label: t("nav.menu"), path: admin_menu_items_path, group: t("nav.groups.sell_serve") }
    end
    if current_user.can?("customers:manage")
      items << { label: t("nav.customers"), path: admin_customers_path, group: t("nav.groups.sell_serve") }
    end

    sales_sidebar_items.each do |tab|
      items << { label: t(tab[:label]), path: public_send(tab[:path]), group: t("nav.sales") }
    end

    if reports_any_access?
      items << { label: t("nav.reports"), path: admin_reports_path, group: t("nav.reports") }
    end

    inventory_sidebar_groups.each do |group|
      group[:tabs].each do |tab|
        items << { label: bt_t(tab[:label]), path: public_send(tab[:path]), group: "#{t('nav.inventory')} · #{t(group[:label])}" }
      end
    end

    accounting_sidebar_groups.each do |group|
      group[:tabs].each do |tab|
        items << { label: t(tab[:label]), path: public_send(tab[:path]), group: "#{t('nav.accounting')} · #{t(group[:label])}" }
      end
    end

    settings_nav_items.each do |item|
      items << { label: item[:label], path: item[:path], group: t("nav.settings") }
    end

    if Current.company.restaurant?
      items << { label: t("nav.pos"), path: pos_path, group: t("nav.groups.launch") } if current_user.can?("pos:access")
      items << { label: t("nav.kitchen"), path: kitchen_path, group: t("nav.groups.launch") } if current_user.can?("kitchen:access")
      items << { label: t("nav.production"), path: production_path, group: t("nav.groups.launch") } if current_user.can?("production:access")
    end

    items
  end

  def permission_label(key)
    fallback = key.to_s.split(":").map { |part| part.tr("_", " ").humanize }.join(" · ")
    t("permissions.keys.#{key.to_s.tr(':', '.')}", default: fallback)
  end

  def permission_group_label(group)
    t("permissions.groups.#{group}", default: group.to_s.humanize)
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

  # e.g. "15d +1 −0.5" — matches monthly payroll attendance breakdown.
  def payroll_attendance_days_label(summary)
    return unless summary&.attendance_recorded

    label = +"#{number_with_precision(summary.payable_days, precision: 2, strip_insignificant_zeros: true)}"
    label << t("accounting.monthly_payroll.days_short")
    if summary.bonus_days.to_d.positive?
      label << " +#{number_with_precision(summary.bonus_days, precision: 2, strip_insignificant_zeros: true)}"
    end
    if summary.penalty_days.to_d.positive?
      label << " −#{number_with_precision(summary.penalty_days, precision: 2, strip_insignificant_zeros: true)}"
    end
    label
  end

  def notification_type_label(type)
    return t("notifications.types.unknown") if type.blank?

    t("notifications.types.#{type}", default: type.titleize)
  end

  def notification_type_class(type)
    case type
    when "inventory" then "bg-amber-100 text-amber-900"
    when "accounting" then "bg-blue-100 text-blue-900"
    when "sales" then "bg-purple-100 text-purple-900"
    else "bg-gray-100 text-gray-700"
    end
  end

  def notification_type_border_class(type)
    case type
    when "inventory" then "border-amber-200"
    when "accounting" then "border-blue-200"
    when "sales" then "border-purple-200"
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
    if raw[:balance_cents].present?
      raw[:balance] = format_money(raw[:balance_cents].to_i)
    end
    if raw[:unit].present?
      raw[:unit] = ingredient_unit_label(raw[:unit])
    end
    if raw[:old_price_cents].present?
      raw[:old_price] = format_money(raw[:old_price_cents].to_i)
    end
    if raw[:new_price_cents].present?
      raw[:new_price] = format_money(raw[:new_price_cents].to_i)
    end
    if raw[:direction].present?
      raw[:arrow] = raw[:direction] == "up" ? "▲" : "▼"
    end

    # Replace plain ingredient name, supplier name, and invoice number with links when IDs are stored.
    has_links = false
    if raw[:ingredient_id].present? && raw[:name].present?
      raw[:name] = link_to(raw[:name], admin_inventory_ingredient_path(raw[:ingredient_id]),
                           class: "font-medium text-blue-600 hover:underline").html_safe
      has_links = true
    end
    if raw[:supplier_id].present? && raw[:supplier].present?
      raw[:supplier] = link_to(raw[:supplier], admin_inventory_supplier_path(raw[:supplier_id]),
                               class: "font-medium text-blue-600 hover:underline").html_safe
      has_links = true
    end
    if raw[:vendor_invoice_id].present? && raw[:invoice_number].present?
      raw[:invoice_number] = link_to(raw[:invoice_number], admin_inventory_vendor_invoice_path(raw[:vendor_invoice_id]),
                                     class: "font-medium text-blue-600 hover:underline").html_safe
      has_links = true
    end
    if raw[:customer_invoice_id].present? && raw[:invoice_number].present?
      raw[:invoice_number] = link_to(raw[:invoice_number], admin_sales_customer_invoice_path(raw[:customer_invoice_id]),
                                     class: "font-medium text-blue-600 hover:underline").html_safe
      has_links = true
    end

    msg = t("notifications.messages.#{key}", **raw.symbolize_keys, default: legacy)
    has_links ? msg.html_safe : msg
  end

  def account_type_classes(account_type)
    case account_type
    when "asset"     then "bg-blue-100 text-blue-700 border border-blue-200"
    when "liability" then "bg-red-100 text-red-700 border border-red-200"
    when "equity"    then "bg-emerald-100 text-emerald-700 border border-emerald-200"
    when "revenue"   then "bg-teal-100 text-teal-700 border border-teal-200"
    when "expense"   then "bg-orange-100 text-orange-700 border border-orange-200"
    else                  "bg-gray-100 text-gray-600 border border-gray-200"
    end
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

  private

  def fallback_je_source_label(je)
    generic_source_label(je.source_record_type, je.source_record_id)
  end
end
