# frozen_string_literal: true

module InventoryReportsHelper
  # Quantities in the valued inventory reports: up to 3 decimals, no trailing zeros.
  def report_qty(quantity)
    return "—" if quantity.nil?

    number_with_precision(quantity, precision: 3, strip_insignificant_zeros: true, delimiter: ",")
  end

  # Marks a value built from a reconstructed (not recorded) unit cost.
  def estimated_cost_mark(count)
    return "" unless count.to_i.positive?

    tag.span("*", class: "text-amber-600 font-bold", title: t("inventory.reports.shared.estimated_hint"))
  end
end
