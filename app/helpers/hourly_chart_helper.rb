# frozen_string_literal: true

# Hour-of-day labels for the by-hour charts (sales report, dashboard live card),
# in 12-hour format.
module HourlyChartHelper
  # Axis label: "6 AM" / "6 ص".
  def hour_axis_label(hour)
    "#{twelve_hour(hour)} #{meridiem(hour)}"
  end

  # Tooltip title: "6:00 AM – 7:00 AM".
  def hour_range_label(hour)
    t("hourly_chart.range", from: hour_clock(hour), to: hour_clock((hour + 1) % 24))
  end

  private

  def hour_clock(hour)
    "#{twelve_hour(hour)}:00 #{meridiem(hour)}"
  end

  def twelve_hour(hour)
    (hour % 12).zero? ? 12 : hour % 12
  end

  def meridiem(hour)
    t(hour < 12 ? "hourly_chart.am" : "hourly_chart.pm")
  end
end
