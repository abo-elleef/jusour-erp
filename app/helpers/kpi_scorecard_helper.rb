# frozen_string_literal: true

module KpiScorecardHelper
  def kpi_value(value, unit)
    return tag.span("–", class: "text-gray-300") if value.nil?

    case unit
    when :amount then format_amount(value)
    when :percent then number_to_percentage(value, precision: 1)
    when :days then t("accounting.kpi.days", count: value.round)
    end
  end

  # An arrow for the change against the previous month, green when it moved
  # the good way. No arrow when either month is unknown or nothing changed.
  def kpi_trend(key, value, previous)
    return if value.nil? || previous.nil? || value.round(1) == previous.round(1)

    up = value > previous
    good = up == ::Accounting::KpiScorecardService::HIGHER_IS_BETTER.include?(key)
    tag.span(up ? "▲" : "▼", class: "text-[10px] #{good ? 'text-green-600' : 'text-red-600'}",
                             title: t(good ? "accounting.kpi.better" : "accounting.kpi.worse"))
  end
end
