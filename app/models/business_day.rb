# frozen_string_literal: true

# Operating day for the restaurant.
#
# Mode is per branch (automatic | manual).
# Automatic: day boundary from start hour (branch override, else company default).
# Manual: each branch has an open LocationOperatingDay advanced by owners.
module BusinessDay
  DEFAULT_START_HOUR = 6
  MODES = %w[automatic manual].freeze
  DEFAULT_MODE = "automatic"

  module_function

  def mode(location:)
    raise ArgumentError, "location is required" if location.blank?

    value = location.business_day_mode.to_s
    MODES.include?(value) ? value : DEFAULT_MODE
  end

  def automatic?(location:)
    mode(location: location) == "automatic"
  end

  def manual?(location:)
    mode(location: location) == "manual"
  end

  # Company-wide default start hour (Business days hub header).
  def company_start_hour
    Setting.get_int("business_day_start_hour", DEFAULT_START_HOUR)
  end

  # Effective cutoff hour. Branch override when set, otherwise company default.
  def start_hour(location: nil)
    if location.present? && location.business_day_start_hour.present?
      location.business_day_start_hour
    else
      company_start_hour
    end
  end

  # Clock-derived date. With +location+, uses that branch's effective start hour.
  def clock_today(location: nil)
    (Time.current.in_time_zone - start_hour(location: location).hours).to_date
  end

  # Operating day for a timestamp. Manual branch → open operating day.
  # Automatic branch (or no location) → clock formula with effective hour.
  def for(time, location: nil)
    if location.present? && manual?(location: location)
      today(location: location)
    else
      (time.in_time_zone - start_hour(location: location).hours).to_date
    end
  end

  # Current operating day. Manual branch → open LocationOperatingDay.
  # Automatic / no location → clock with effective hour.
  def today(location: nil)
    if location.present? && manual?(location: location)
      ensure_current_day!(location).business_date
    else
      clock_today(location: location)
    end
  end

  def range(date, location: nil)
    d = date.to_date
    hour = start_hour(location: location)
    start = Time.zone.local(d.year, d.month, d.day, hour)
    start...(start + 1.day)
  end

  def range_between(from_date, to_date, location: nil)
    range(from_date, location: location).begin...range(to_date, location: location).end
  end

  def ensure_current_day!(location, user: nil)
    LocationOperatingDay.current_for(location) ||
      LocationOperatingDay.ensure_open!(location, date: clock_today(location: location), user: user)
  end

  def apply_mode!(location, mode, user: nil)
    raise ArgumentError, "location is required" if location.blank?

    next_mode = mode.to_s
    raise ArgumentError, "invalid mode" unless MODES.include?(next_mode)

    previous = mode(location: location)
    location.update!(business_day_mode: next_mode)
    ensure_current_day!(location, user: user) if previous != "manual" && next_mode == "manual"
    location
  end
end
