# frozen_string_literal: true

# Central definition of the "operating day" for a restaurant that trades past
# midnight. The day boundary is shifted from 00:00 to a per-company cutoff hour
# (default 6 AM, Cairo time): everything from midnight up to the cutoff counts
# toward the PREVIOUS operating day.
#
#   business_day(timestamp) = (timestamp − cutoff_hours).to_date
#
# `created_at` timestamps remain the single source of truth — this only shifts
# where the day boundary sits, so range queries keep using the created_at index.
module BusinessDay
  DEFAULT_START_HOUR = 6

  # Per-company cutoff hour (0–23). Falls back to the default when there is no
  # current company (rake tasks, console) or no stored setting.
  def self.start_hour
    Setting.get_int("business_day_start_hour", DEFAULT_START_HOUR)
  end

  # The operating day a given instant belongs to.
  def self.for(time)
    (time.in_time_zone - start_hour.hours).to_date
  end

  # The operating day that is currently in progress.
  def self.today
    self.for(Time.current)
  end

  # Half-open created_at range [start, next_start) covering one operating day,
  # e.g. operating day 2026-01-09 with a 6 AM cutoff → [Jan 9 06:00, Jan 10 06:00).
  def self.range(date)
    d = date.to_date
    start = Time.zone.local(d.year, d.month, d.day, start_hour)
    start...(start + 1.day)
  end

  # Half-open created_at range spanning operating days from_date..to_date (inclusive).
  def self.range_between(from_date, to_date)
    range(from_date).begin...range(to_date).end
  end
end
