# frozen_string_literal: true

# Presentation for the unit-conversion review: turning a reviewed row's status
# and expected factor into the sentence a reviewer can act on.
module UnitConversionsHelper
  # Why this row is flagged (or vouched for), in words. Nil when nothing in the
  # data can speak to it — the reviewer's own judgement is all there is.
  def unit_conversion_reason(row)
    base = unit_name_tag(row.base_unit)
    alt  = unit_name_tag(row.alt_unit)

    case row.basis
    when :identity
      t("inventory.unit_conversions.reason.identity_html", base: base)
    when :physical
      t("inventory.unit_conversions.reason.physical_html",
        expected: format_conversion_factor(row.expected), alt: alt, base: base)
    when :pack
      t("inventory.unit_conversions.reason.pack_html",
        expected: format_conversion_factor(row.expected), alt: alt, base: base)
    when :peer
      t("inventory.unit_conversions.reason.peer_html",
        count: row.peer_count, expected: format_conversion_factor(row.expected))
    end
  end

  # Unit names are written in Arabic while the interface may be English (and the
  # other way round). Left bare, a name like "كرتونة * 12" reorders the digits
  # of the sentence around it; isolating it keeps both readable.
  def unit_name_tag(unit)
    tag.bdi(Ingredient.unit_display_label(unit))
  end

  # The same sentence without the bidi markup, for the CSV export.
  def unit_conversion_reason_text(row)
    html = unit_conversion_reason(row)
    return nil if html.blank?

    CGI.unescapeHTML(strip_tags(html))
  end

  def unit_conversion_status_class(status)
    case status
    when :check then "bg-red-50 text-red-700 border-red-200"
    when :ok then "bg-emerald-50 text-emerald-700 border-emerald-200"
    else "bg-gray-50 text-gray-600 border-gray-200"
    end
  end

  # Factors span 0.0001 to 1000 — trailing zeros on either end make a column of
  # them unreadable, so strip them and keep the four decimals the column holds.
  def format_conversion_factor(factor)
    return "—" if factor.blank?

    number_with_precision(factor, precision: 4, strip_insignificant_zeros: true, delimiter: "")
  end

  # What one alternate unit costs, from the ingredient's kept unit cost — a
  # wrong factor usually shows up here first ("a carton of oil costs 4?").
  def unit_conversion_cost(row)
    format_amount((row.ingredient.cost_per_unit_cents.to_i * row.factor).round)
  end

  # Stock on hand expressed in the alternate unit, so the number can be held up
  # against what is actually on the shelf.
  def unit_conversion_on_hand(row)
    return "—" unless row.factor.positive?

    number_with_precision(row.ingredient.quantity_on_hand.to_d / row.factor,
      precision: 2, strip_insignificant_zeros: true)
  end
end
